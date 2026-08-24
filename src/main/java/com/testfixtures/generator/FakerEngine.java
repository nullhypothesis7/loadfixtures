package com.testfixtures.generator;

import com.github.javafaker.Faker;
import com.testfixtures.model.PipeDefinition.ColumnDefinition;

import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;

public class FakerEngine {

    private final Faker faker;

    public FakerEngine(Faker faker) {
        this.faker = faker;
    }

    public Object generate(ColumnDefinition col, long sequence) {
        return generate(col, sequence, null);
    }

    /**
     * @param tableName the pipe's own target table, needed to derive stable
     *                  PK UUIDs (see {@link #deterministicUuid}); may be null
     *                  for callers that never generate a UUID PK/FK column.
     */
    public Object generate(ColumnDefinition col, long sequence, String tableName) {
        return switch (col.getType()) {
            case "NULL_VALUE"       -> null;
            case "SEQUENCE"         -> sequence;
            case "FIRST_NAME"       -> faker.name().firstName();
            case "LAST_NAME"        -> faker.name().lastName();
            case "EMAIL"            -> faker.internet().emailAddress();
            case "DATE_PAST"        -> randomDateWithinLastFiveYears();
            case "ENUM"             -> randomEnum(col.getValues());
            case "PHONE"            -> boundedPhone(col);
            // UUID PKs can't rely on a real UUID.randomUUID() the way a plain
            // "generate something unique" column could — a child row's FK_UUID
            // column (below) needs to be able to independently recompute the
            // exact same value for "row N of this table" without any shared
            // runtime state. Deriving it from (table, row index) makes that
            // possible; a truly random UUID would make FK resolution impossible.
            case "UUID"             -> deterministicUuid(tableName, sequence);
            case "BOOLEAN"          -> ThreadLocalRandom.current().nextBoolean();
            case "UNIQUE_STRING"    -> String.format("U%07d", sequence);
            case "STRING_FK"        -> String.format("U%07d", randomInt(col.getValues()));
            case "JSONB"            -> pgObject("jsonb", "{}");
            case "INET"             -> pgObject("inet", "10.0." + ThreadLocalRandom.current().nextInt(0, 256)
                                              + "." + ThreadLocalRandom.current().nextInt(1, 255));
            // A String[] here, not a PGobject like JSONB/INET above — Postgres
            // arrays bind through java.sql.Array (JdbcSink builds that via
            // Connection.createArrayOf(), which needs a live connection
            // FakerEngine doesn't have), not through the PGobject mechanism
            // that works fine for genuinely scalar extended types.
            case "TEXT_ARRAY"       -> new String[] { "value1", "value2" };
            case "CURRENCY_AMOUNT"  -> randomAmount(col, 999999.99);
            case "SMALL_AMOUNT"     -> randomAmount(col, 99.99);
            case "RANDOM_INT"       -> randomInt(col.getValues());
            case "FK_INT"           -> randomInt(col.getValues());
            case "NULLABLE_FK_INT"  -> ThreadLocalRandom.current().nextInt(5) == 0
                                       ? null : randomInt(col.getValues());
            // Same predictable-range trick FK_INT uses (parent has rows
            // [1, totalRows], pick one at random) — the only difference is the
            // picked index gets turned into a UUID via the same deterministic
            // derivation the parent used for its own PK, instead of being
            // inserted as the value directly.
            case "FK_UUID"          -> deterministicUuid(col.getRefTable(), randomInt(col.getValues()));
            case "NULLABLE_FK_UUID" -> ThreadLocalRandom.current().nextInt(5) == 0
                                       ? null : deterministicUuid(col.getRefTable(), randomInt(col.getValues()));
            // Real Salesforce record Id: 18 chars, a 3-char object key prefix
            // (values[0] for the PK case, values[2] for the FK case — see
            // PipeBuilder), then a checksum-validated body derived from
            // (prefix, row index) the same way deterministicUuid derives from
            // (table, index) — so FK_SF_ID can independently recompute a
            // parent's exact Id without shared runtime state.
            case "SF_ID"            -> salesforceId(col.getValues().get(0), sequence);
            case "FK_SF_ID"         -> salesforceId(col.getValues().get(2), randomInt(col.getValues()));
            case "NULLABLE_FK_SF_ID" -> ThreadLocalRandom.current().nextInt(5) == 0
                                       ? null : salesforceId(col.getValues().get(2), randomInt(col.getValues()));
            default                 -> faker.lorem().word();
        };
    }

    /**
     * A stable, repeatable UUID for "row {@code index} of {@code table}" —
     * UUIDv3 (name-based, MD5) over "{table}#{index}". Same inputs always
     * produce the same UUID, which is what lets an FK_UUID column on a child
     * pipe reproduce a parent's PK value without any shared runtime state
     * (the same mechanism FK_INT gets for free from sequential integer PKs).
     */
    private String deterministicUuid(String table, long index) {
        String name = table + "#" + index;
        return java.util.UUID.nameUUIDFromBytes(
                name.getBytes(java.nio.charset.StandardCharsets.UTF_8)).toString();
    }

    private static final String SF_ID_BODY_ALPHABET =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    private static final String SF_ID_CHECKSUM_ALPHABET =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";

    /**
     * A stable, repeatable 18-character Salesforce-shaped record Id for row
     * {@code index} of the object identified by {@code keyPrefix} — the same
     * deterministic-derivation trick {@link #deterministicUuid} uses, applied
     * to a fixed-format, checksum-validated scheme instead of a UUID.
     *
     * Real Salesforce Ids encode pod/instance/counter information in their
     * 12-character body; this doesn't attempt to replicate that internal
     * structure (there's nothing external that could validate it), only the
     * parts that make an Id look and behave like a real one: the correct
     * 3-char object key prefix, 18 total characters, and a checksum suffix
     * computed by Salesforce's actual, publicly documented algorithm — the
     * capitalization pattern of the first 15 characters, taken in three
     * 5-char groups, each mapped to one of 32 checksum characters. Hashing
     * the body from "{prefix}#{index}" (MD5, like the UUID case) is what
     * lets an FK_SF_ID column recompute a parent's exact Id from nothing but
     * (parent's prefix, chosen row index).
     */
    private String salesforceId(String keyPrefix, long index) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("MD5")
                    .digest((keyPrefix + "#" + index).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            StringBuilder body = new StringBuilder(12);
            for (int i = 0; i < 12; i++) {
                body.append(SF_ID_BODY_ALPHABET.charAt(
                        Byte.toUnsignedInt(digest[i]) % SF_ID_BODY_ALPHABET.length()));
            }
            String id15 = keyPrefix + body;
            StringBuilder checksum = new StringBuilder(3);
            for (int chunk = 0; chunk < 3; chunk++) {
                int bits = 0;
                for (int i = 0; i < 5; i++) {
                    if (Character.isUpperCase(id15.charAt(chunk * 5 + i))) bits |= (1 << i);
                }
                checksum.append(SF_ID_CHECKSUM_ALPHABET.charAt(bits));
            }
            return id15 + checksum;
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }

    private LocalDate randomDateWithinLastFiveYears() {
        LocalDate end = LocalDate.now();
        LocalDate start = end.minusYears(5);
        long startEpoch = start.toEpochDay();
        long endEpoch = end.toEpochDay();
        return LocalDate.ofEpochDay(ThreadLocalRandom.current().nextLong(startEpoch, endEpoch));
    }

    private String boundedPhone(ColumnDefinition col) {
        String phone = faker.phoneNumber().phoneNumber();
        List<String> values = col.getValues();
        if (values != null && !values.isEmpty()) {
            try {
                int maxLength = Integer.parseInt(values.get(0));
                if (phone.length() > maxLength) phone = phone.substring(0, maxLength);
            } catch (NumberFormatException ignored) {
                // fall through to unbounded phone
            }
        }
        return phone;
    }

    private String randomEnum(List<String> values) {
        return values.get(ThreadLocalRandom.current().nextInt(values.size()));
    }

    // values[0] = min (inclusive), values[1] = max (inclusive)
    private int randomInt(List<String> values) {
        int min = Integer.parseInt(values.get(0));
        int max = Integer.parseInt(values.get(1));
        return ThreadLocalRandom.current().nextInt(min, max + 1);
    }

    /**
     * @param defaultMax used when {@code col} carries no column-specific ceiling
     *                   (hand-authored pipe JSON never sets one) — preserves
     *                   the original hardcoded-range behavior for those.
     */
    private java.math.BigDecimal randomAmount(ColumnDefinition col, double defaultMax) {
        double max = defaultMax;
        int scale = 2;
        List<String> values = col.getValues();
        if (values != null && !values.isEmpty()) {
            try {
                max = Double.parseDouble(values.get(0));
                if (values.size() > 1) scale = Integer.parseInt(values.get(1));
            } catch (NumberFormatException ignored) {
                // fall through to defaultMax/scale
            }
        }
        double raw = ThreadLocalRandom.current().nextDouble(0.01, Math.max(max, 0.02));
        java.math.BigDecimal rounded = java.math.BigDecimal.valueOf(raw)
                .setScale(scale, java.math.RoundingMode.HALF_UP);
        // Rounding to the column's real scale (not always 2dp — see
        // PipeBuilder) can still push a draw taken right at the ceiling over
        // it: 99.9995 rounds to 100.000 at scale 3, breaching a NUMERIC(5,3)
        // column's true max of 99.999. Clamp back down to the ceiling itself
        // (truncated to the same scale) rather than re-drawing.
        java.math.BigDecimal ceiling = java.math.BigDecimal.valueOf(max)
                .setScale(scale, java.math.RoundingMode.DOWN);
        return rounded.compareTo(ceiling) > 0 ? ceiling : rounded;
    }

    private org.postgresql.util.PGobject pgObject(String type, String value) {
        try {
            org.postgresql.util.PGobject obj = new org.postgresql.util.PGobject();
            obj.setType(type);
            obj.setValue(value);
            return obj;
        } catch (java.sql.SQLException e) {
            throw new RuntimeException(e);
        }
    }
}
