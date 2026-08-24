#!/usr/bin/env python3
"""
scripts/bank_loader.py

Introspects the pgbank FK graph across all named schemas, topologically
sorts the 88-table bank_schema, then inserts N rows per table in
dependency order.  Self-contained; no app stack required.

Usage:
    python3 scripts/bank_loader.py [--rows N]   (default 75)
"""
import json, random, string, uuid, datetime, re, sys, argparse
from collections import defaultdict, deque

import psycopg2
import psycopg2.extras

# ── connection ────────────────────────────────────────────────────────────────

DSN = "host=localhost port=5436 dbname=bankschemadb user=bankschemauser password=bankschemapass"

SCHEMAS = ('ref', 'audit', 'party', 'account', 'txn',
           'lending', 'card', 'compliance', 'ops', 'wart')

# ── seed data for pure-reference tables (string PKs) ─────────────────────────

COUNTRIES = [
    ('US','United States','USA','840','Americas',False),
    ('GB','United Kingdom','GBR','826','Europe',  False),
    ('DE','Germany',       'DEU','276','Europe',  False),
    ('FR','France',        'FRA','250','Europe',  False),
    ('CA','Canada',        'CAN','124','Americas',False),
    ('AU','Australia',     'AUS','036','Oceania', False),
    ('JP','Japan',         'JPN','392','Asia',    False),
    ('SG','Singapore',     'SGP','702','Asia',    False),
    ('CH','Switzerland',   'CHE','756','Europe',  False),
    ('MX','Mexico',        'MEX','484','Americas',False),
    ('BR','Brazil',        'BRA','076','Americas',False),
    ('IN','India',         'IND','356','Asia',    False),
    ('KP','North Korea',   'PRK','408','Asia',    True),
    ('IR','Iran',          'IRN','364','Asia',    True),
]

CURRENCIES = [
    ('USD','US Dollar',         '840',2,True),
    ('EUR','Euro',              '978',2,True),
    ('GBP','British Pound',     '826',2,True),
    ('CAD','Canadian Dollar',   '124',2,True),
    ('AUD','Australian Dollar', '036',2,True),
    ('JPY','Japanese Yen',      '392',0,True),
    ('CHF','Swiss Franc',       '756',2,True),
    ('SGD','Singapore Dollar',  '702',2,True),
    ('MXN','Mexican Peso',      '484',2,True),
    ('BRL','Brazilian Real',    '986',2,True),
]

# ── introspection ─────────────────────────────────────────────────────────────

def load_tables(conn):
    sl = ','.join(f"'{s}'" for s in SCHEMAS)
    with conn.cursor() as cur:
        cur.execute(f"""
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN ({sl}) AND table_type = 'BASE TABLE'
            ORDER BY table_schema, table_name
        """)
        return [(r[0], r[1]) for r in cur.fetchall()]


def load_fk_edges(conn):
    """Return list of dicts: child_table, child_col, parent_table, parent_col, nullable."""
    sl = ','.join(f"'{s}'" for s in SCHEMAS)
    with conn.cursor() as cur:
        cur.execute(f"""
            SELECT DISTINCT
                kcu.table_schema  || '.' || kcu.table_name  AS child_table,
                kcu.column_name                              AS child_col,
                ccu.table_schema  || '.' || ccu.table_name  AS parent_table,
                ccu.column_name                              AS parent_col,
                cols.is_nullable                             AS nullable
            FROM information_schema.referential_constraints rc
            JOIN information_schema.key_column_usage kcu
              ON kcu.constraint_name   = rc.constraint_name
             AND kcu.constraint_schema = rc.constraint_schema
            JOIN information_schema.constraint_column_usage ccu
              ON ccu.constraint_name   = rc.unique_constraint_name
             AND ccu.constraint_schema = rc.unique_constraint_schema
            JOIN information_schema.columns cols
              ON cols.table_schema = kcu.table_schema
             AND cols.table_name   = kcu.table_name
             AND cols.column_name  = kcu.column_name
            WHERE kcu.table_schema IN ({sl})
            ORDER BY child_table, child_col
        """)
        return [
            dict(child_table=r[0], child_col=r[1],
                 parent_table=r[2], parent_col=r[3],
                 nullable=(r[4] == 'YES'))
            for r in cur.fetchall()
        ]


def load_columns(conn, schema, table):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT column_name, data_type, udt_name, is_nullable,
                   column_default, character_maximum_length
            FROM information_schema.columns
            WHERE table_schema=%s AND table_name=%s
            ORDER BY ordinal_position
        """, (schema, table))
        return [dict(name=r[0], dtype=r[1], udt=r[2],
                     nullable=(r[3]=='YES'), default=r[4], maxlen=r[5])
                for r in cur.fetchall()]


def load_check_enums(conn, schema, table):
    """Return {col: [allowed_values]} parsed from pg_constraint.
    information_schema.check_constraints only stores NOT NULL checks, not IN-list
    enums; pg_get_constraintdef gives the real clause for both VARCHAR (::character
    varying) and CHAR (::bpchar) columns.
    """
    result = {}
    with conn.cursor() as cur:
        cur.execute("""
            SELECT pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE conrelid = %s::regclass AND contype = 'c'
        """, (f"{schema}.{table}",))
        for (clause,) in cur.fetchall():
            # VARCHAR format: ((col)::text = ANY ((ARRAY['V'::character varying, ...])::text[]))
            col_m = re.search(r'\((\w+)\)::text\s*=\s*ANY', clause)
            if col_m:
                col  = col_m.group(1)
                vals = re.findall(r"'([^']+)'::character varying", clause)
                if vals:
                    result[col] = vals
                    continue

            # CHAR format: (col = ANY (ARRAY['I'::bpchar, 'U'::bpchar, ...]))
            col_m = re.search(r'CHECK\s*\(\(?(\w+)\s*=\s*ANY', clause)
            if col_m:
                col  = col_m.group(1)
                vals = re.findall(r"'([^']+)'::bpchar", clause)
                if vals:
                    result[col] = vals
    return result

# ── topological sort (Kahn's algorithm) ──────────────────────────────────────

def topological_sort(tables, fk_edges):
    table_set = {f"{s}.{t}" for s, t in tables}
    in_deg    = defaultdict(int)
    children  = defaultdict(set)   # parent → set of children

    for e in fk_edges:
        c, p = e['child_table'], e['parent_table']
        if c == p:              # skip self-referencing edges
            continue
        if c not in table_set or p not in table_set:
            continue
        if c not in children[p]:
            children[p].add(c)
            in_deg[c] += 1

    for t in table_set:
        in_deg.setdefault(t, 0)

    queue  = deque(sorted(t for t in table_set if in_deg[t] == 0))
    result = []
    while queue:
        node = queue.popleft()
        result.append(node)
        for child in sorted(children[node]):
            in_deg[child] -= 1
            if in_deg[child] == 0:
                queue.append(child)

    # Anything left has cycles (self-refs handled above; shouldn't happen here)
    remaining = sorted(t for t in table_set if t not in set(result))
    result.extend(remaining)
    return result

# ── data generation ───────────────────────────────────────────────────────────

WORDS = ['alpha','bravo','charlie','delta','echo','foxtrot','golf','hotel',
         'india','juliet','kilo','lima','mike','november','oscar','papa',
         'quebec','romeo','sierra','tango','uniform','victor','whiskey',
         'xray','yankee','zulu']

FIRST_NAMES = ['James','Mary','John','Patricia','Robert','Jennifer',
               'Michael','Linda','William','Barbara','David','Susan',
               'Richard','Jessica','Joseph','Sarah','Thomas','Karen']
LAST_NAMES  = ['Smith','Johnson','Williams','Brown','Jones','Garcia',
               'Miller','Davis','Rodriguez','Martinez','Hernandez','Lopez',
               'Wilson','Anderson','Taylor','Thomas','Moore','Jackson']
CITIES      = ['New York','London','Toronto','Sydney','Berlin','Paris',
               'Singapore','Tokyo','Chicago','Los Angeles','Frankfurt']
US_STATES   = ['NY','CA','TX','FL','IL','PA','OH','GA','NC','WA']
COUNTRY_CODES = [r[0] for r in COUNTRIES]
CURRENCY_CODES = [r[0] for r in CURRENCIES]


def rstr(n=8):
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=n))


def gen_value(col, check_enums, fk_cache, fk_map, seq, unique_used):
    name    = col['name']
    dtype   = col['dtype']
    udt     = col['udt']
    default = col['default']
    maxlen  = col['maxlen']
    nullable = col['nullable']

    # ── auto-generated serials: omit, let DB fill ─────────────────────────────
    if default and 'nextval' in default:
        return None  # sentinel → excluded from INSERT

    # ── FK column ─────────────────────────────────────────────────────────────
    if name in fk_map:
        info  = fk_map[name]
        key   = f"{info['parent_table']}.{info['parent_col']}"
        pool  = fk_cache.get(key, [])
        if pool:
            if name in unique_used:           # UNIQUE FK col (e.g. original_txn_id)
                avail = [v for v in pool if v not in unique_used[name]]
                if avail:
                    v = random.choice(avail)
                    unique_used[name].add(v)
                    return v
            return random.choice(pool)
        # Parent cache is empty — no valid FK value exists yet.
        # Return None for both nullable and non-nullable cases; the savepoint in
        # insert_table will catch the resulting constraint violation and skip the row.
        # Never fall back to 1: it is the wrong type for string/UUID PKs and may
        # not exist for integer PKs, producing silent data corruption either way.
        return None

    # ── CHECK enum ────────────────────────────────────────────────────────────
    if name in check_enums:
        return random.choice(check_enums[name])

    # ── boolean ───────────────────────────────────────────────────────────────
    if dtype == 'boolean':
        return False if 'deleted' in name else random.choice([True, False])

    # ── uuid ──────────────────────────────────────────────────────────────────
    if dtype == 'uuid' or udt == 'uuid':
        return str(uuid.uuid4())

    # ── arrays ────────────────────────────────────────────────────────────────
    if dtype == 'ARRAY' or udt.startswith('_'):
        return ['val1', 'val2']

    # ── jsonb / json ──────────────────────────────────────────────────────────
    if dtype in ('jsonb', 'json'):
        return psycopg2.extras.Json({'k': random.choice(WORDS),
                                     'v': random.randint(1, 100)})

    # ── inet ──────────────────────────────────────────────────────────────────
    if dtype == 'inet':
        return (f"{random.randint(10,199)}.{random.randint(0,255)}"
                f".{random.randint(0,255)}.{random.randint(1,254)}")

    # ── numeric ───────────────────────────────────────────────────────────────
    if dtype in ('numeric', 'decimal', 'money', 'real', 'double precision'):
        n = name.lower()
        if any(x in n for x in ('pct','rate','ratio','score')):
            return round(random.uniform(0.01, 30.0), 4)
        if any(x in n for x in ('seq','order','count','version','tier','units')):
            return random.randint(1, 50)
        return round(random.uniform(0.01, 999999.99), 2)

    # ── date ──────────────────────────────────────────────────────────────────
    if dtype == 'date':
        return datetime.date.today() - datetime.timedelta(days=random.randint(1, 365*4))

    # ── timestamps ────────────────────────────────────────────────────────────
    if 'timestamp' in dtype or dtype == 'time':
        return (datetime.datetime.now()
                - datetime.timedelta(seconds=random.randint(0, 365*4*86400)))

    # ── integer types (non-FK, non-serial) ────────────────────────────────────
    if dtype in ('integer', 'bigint', 'smallint', 'int', 'int2', 'int4', 'int8'):
        n = name.lower()
        if any(x in n for x in ('seq','count','order','version','day','month',
                                  'year','size','units','score','tier','period',
                                  'attempt','priority','pos')):
            return random.randint(1, 60)
        return random.randint(1, 999999)

    # ── CHAR(n) ───────────────────────────────────────────────────────────────
    if dtype == 'character' and maxlen:
        n = name.lower()
        if maxlen == 1:
            return random.choice(['D', 'C', 'A', 'S', 'Y', 'N'])
        if maxlen == 2:
            return random.choice(COUNTRY_CODES)
        if maxlen == 3:
            return random.choice(CURRENCY_CODES)
        if maxlen == 4:
            return str(random.randint(1000, 9999))
        return rstr(maxlen)[:maxlen]

    # ── VARCHAR / TEXT ────────────────────────────────────────────────────────
    if dtype in ('character varying', 'text'):
        n = name.lower()

        # Unique-identity fields: always use a UUID-derived value
        if any(x in n for x in ('hash', 'token', 'secret')):
            v = str(uuid.uuid4())
            return v[:maxlen] if maxlen else v

        if 'email' in n:
            fn = random.choice(FIRST_NAMES).lower()
            ln = random.choice(LAST_NAMES).lower()
            v  = f"{fn}.{ln}{random.randint(1,9999)}@example.com"
            return v[:maxlen] if maxlen else v

        if 'phone' in n or 'fax' in n:
            v = f"+1-{random.randint(200,999)}-{random.randint(100,999)}-{random.randint(1000,9999)}"
            return v[:maxlen] if maxlen else v

        if 'first_name' in n:
            return random.choice(FIRST_NAMES)[:maxlen] if maxlen else random.choice(FIRST_NAMES)
        if 'last_name' in n:
            return random.choice(LAST_NAMES)[:maxlen] if maxlen else random.choice(LAST_NAMES)

        if n.endswith('_name') or n == 'name':
            v = f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"
            return v[:maxlen] if maxlen else v

        # Unique-enough short codes: refs, codes, numbers, keys
        if any(n.endswith(sfx) for sfx in ('_ref','_code','_key','_id')):
            v = rstr(min(maxlen or 20, 20))
            return v[:maxlen] if maxlen else v
        if 'number' in n:
            v = rstr(min(maxlen or 16, 16))
            return v[:maxlen] if maxlen else v
        if 'ref' in n:
            v = rstr(8)
            return v[:maxlen] if maxlen else v

        if any(x in n for x in ('url', 'uri', 'link', 'website')):
            return ('https://example.com/' + rstr(6))[:maxlen] if maxlen else 'https://example.com/' + rstr(6)

        if any(x in n for x in ('description', 'narrative', 'notes',
                                  'reason', 'resolution', 'memo', 'clause',
                                  'purpose', 'remittance', 'addenda')):
            v = ' '.join(random.choices(WORDS, k=5))
            return v[:maxlen] if maxlen else v

        if any(x in n for x in ('address', 'line1', 'line2')):
            v = f"{random.randint(1,9999)} {random.choice(LAST_NAMES)} St"
            return v[:maxlen] if maxlen else v
        if 'city' in n:
            v = random.choice(CITIES)
            return v[:maxlen] if maxlen else v
        if 'state' in n or 'province' in n:
            return random.choice(US_STATES)[:maxlen] if maxlen else random.choice(US_STATES)
        if 'country' in n:
            return random.choice(COUNTRY_CODES)[:maxlen] if maxlen else random.choice(COUNTRY_CODES)
        if 'postal' in n or 'zip' in n:
            v = str(random.randint(10000, 99999))
            return v[:maxlen] if maxlen else v

        # Short opaque codes
        if maxlen and maxlen <= 5:
            return rstr(maxlen)
        if maxlen and maxlen <= 20:
            return rstr(min(maxlen, 8))

        # Generic fallback
        v = random.choice(WORDS).capitalize()
        return v[:maxlen] if maxlen else v

    # ── fallback ──────────────────────────────────────────────────────────────
    v = random.choice(WORDS)
    return v[:maxlen] if maxlen else v


# ── insertion ─────────────────────────────────────────────────────────────────

def build_fk_map(fk_edges, table_key):
    """child_col → {parent_table, parent_col, nullable}"""
    result = {}
    for e in fk_edges:
        if e['child_table'] == table_key:
            result[e['child_col']] = {
                'parent_table': e['parent_table'],
                'parent_col':   e['parent_col'],
                'nullable':     e['nullable'],
            }
    return result


def insert_table(conn, schema, table, cols, check_enums, fk_map, fk_cache, n_rows):
    qualified = f"{schema}.{table}"

    # Columns we INSERT (skip auto-serials)
    ins_cols = [c for c in cols if not (c['default'] and 'nextval' in c['default'])]
    if not ins_cols:
        return 0

    col_names    = [c['name'] for c in ins_cols]
    placeholders = ', '.join(['%s'] * len(col_names))
    sql = (f"INSERT INTO {qualified} ({', '.join(col_names)}) "
           f"VALUES ({placeholders}) ON CONFLICT DO NOTHING")

    # Tables with UNIQUE FK constraints that need distinct parent IDs per row
    unique_used = {}
    if table == 'transaction_reversal':
        unique_used['original_txn_id'] = set()

    inserted = 0
    with conn.cursor() as cur:
        for seq in range(1, n_rows + 1):
            row = tuple(
                gen_value(c, check_enums, fk_cache, fk_map, seq, unique_used)
                for c in ins_cols
            )
            # Use a savepoint so a single bad row only rolls back that one row,
            # not the entire batch accumulated so far.
            cur.execute("SAVEPOINT row_sp")
            try:
                cur.execute(sql, row)
                if cur.rowcount > 0:
                    inserted += 1
                cur.execute("RELEASE SAVEPOINT row_sp")
            except Exception as exc:
                cur.execute("ROLLBACK TO SAVEPOINT row_sp")
                print(f"    WARN {qualified} row {seq} skipped — {exc}", file=sys.stderr)
    return inserted


def cache_parent_values(conn, schema, table, fk_edges):
    """After insertion, store referenced-column values for downstream FK resolution."""
    table_key = f"{schema}.{table}"
    ref_cols  = {e['parent_col'] for e in fk_edges if e['parent_table'] == table_key}
    cache     = {}
    with conn.cursor() as cur:
        for col in ref_cols:
            try:
                cur.execute(
                    f"SELECT {col} FROM {table_key} WHERE {col} IS NOT NULL LIMIT 500"
                )
                vals = [r[0] for r in cur.fetchall()]
                if vals:
                    cache[f"{table_key}.{col}"] = vals
            except Exception as exc:
                print(f"    WARN caching {table_key}.{col}: {exc}", file=sys.stderr)
    return cache


# ── seeding ───────────────────────────────────────────────────────────────────

def seed_ref_tables(conn):
    ts = datetime.datetime.now()
    with conn.cursor() as cur:
        for r in COUNTRIES:
            cur.execute("""
                INSERT INTO ref.country
                    (country_code,country_name,alpha3,numeric_code,region,is_sanctioned,
                     created_at,updated_at,is_deleted)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,false) ON CONFLICT DO NOTHING
            """, (*r, ts, ts))
        for r in CURRENCIES:
            cur.execute("""
                INSERT INTO ref.currency
                    (currency_code,currency_name,numeric_code,minor_units,is_active,
                     created_at,updated_at,is_deleted)
                VALUES (%s,%s,%s,%s,%s,%s,%s,false) ON CONFLICT DO NOTHING
            """, (*r, ts, ts))
    conn.commit()
    return len(COUNTRIES), len(CURRENCIES)


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rows',     type=int,  default=75,    help='rows per table (default 75)')
    ap.add_argument('--truncate', action='store_true',      help='truncate all tables first')
    args = ap.parse_args()
    N = args.rows

    conn = psycopg2.connect(DSN)
    conn.autocommit = False

    # ── 1. Introspect ─────────────────────────────────────────────────────────
    print("\n══ STEP 1  Schema introspection ══════════════════════════════════════")
    tables   = load_tables(conn)
    fk_edges = load_fk_edges(conn)
    print(f"  {len(tables)} tables across schemas: {', '.join(sorted({s for s,_ in tables}))}")
    print(f"  {len(fk_edges)} FK edges")

    # ── 2. Topological sort ───────────────────────────────────────────────────
    print("\n══ STEP 2  Topological sort (Kahn's) ═════════════════════════════════")
    ordered = topological_sort(tables, fk_edges)
    print(f"  Insert order for {len(ordered)} tables:")
    for i, t in enumerate(ordered, 1):
        # annotate tables that have FK parents
        parents = sorted({e['parent_table'] for e in fk_edges if e['child_table'] == t})
        ann = f"  ← {', '.join(parents)}" if parents else "  (no deps)"
        print(f"    {i:3d}. {t}{ann}")

    # ── 2b. Optional truncate (reverse topological order avoids FK conflicts) ─
    if args.truncate:
        print("\n══ STEP 2b Truncating all tables (reverse order) ═════════════════════")
        with conn.cursor() as cur:
            for tkey in reversed(ordered):
                cur.execute(f"TRUNCATE {tkey} RESTART IDENTITY CASCADE")
        conn.commit()
        print(f"  Truncated {len(ordered)} tables.")

    # ── 3. Seed string-PK reference tables ───────────────────────────────────
    print("\n══ STEP 3  Seed string-PK reference tables ═══════════════════════════")
    nc, ncu = seed_ref_tables(conn)
    print(f"  ref.country  : {nc} rows")
    print(f"  ref.currency : {ncu} rows")

    # Pre-populate FK cache for the seeded tables
    fk_cache: dict[str, list] = {
        'ref.country.country_code':   [r[0] for r in COUNTRIES],
        'ref.currency.currency_code': [r[0] for r in CURRENCIES],
    }
    skip = {'ref.country', 'ref.currency'}

    # ── 4. Insert in topological order ───────────────────────────────────────
    print(f"\n══ STEP 4  Inserting {N} rows / table ════════════════════════════════")
    total = 0
    for pos, tkey in enumerate(ordered, 1):
        if tkey in skip:
            print(f"  [{pos:3d}/{len(ordered)}] {tkey:45s} (seeded — skip)")
            continue

        schema, tname = tkey.split('.')
        cols        = load_columns(conn, schema, tname)
        check_enums = load_check_enums(conn, schema, tname)
        fk_map      = build_fk_map(fk_edges, tkey)

        n = insert_table(conn, schema, tname, cols, check_enums, fk_map, fk_cache, N)
        conn.commit()

        new_cache = cache_parent_values(conn, schema, tname, fk_edges)
        fk_cache.update(new_cache)
        total += n
        print(f"  [{pos:3d}/{len(ordered)}] {tkey:45s} {n:4d} rows")

    # ── 5. Summary ────────────────────────────────────────────────────────────
    print(f"\n══ DONE  {total:,} rows across {len(ordered)} tables ══════════════════════════\n")

    print("Per-schema row counts (live from DB):")
    for schema in SCHEMAS:
        print(f"\n  schema: {schema}")
        with conn.cursor() as cur:
            cur.execute("""
                SELECT table_name FROM information_schema.tables
                WHERE table_schema=%s AND table_type='BASE TABLE'
                ORDER BY table_name
            """, (schema,))
            tnames = [r[0] for r in cur.fetchall()]
        for tname in tnames:
            with conn.cursor() as cur:
                cur.execute(f"SELECT COUNT(*) FROM {schema}.{tname}")
                cnt = cur.fetchone()[0]
            print(f"    {tname:40s} {cnt:>6} rows")

    conn.close()


if __name__ == '__main__':
    main()
