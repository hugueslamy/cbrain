-- Run once by the MariaDB image, when the db_data volume is new.
-- MARIADB_DATABASE only creates cbrain_dev; the 'test' service (RSpec)
-- uses its own database, with the same user.
CREATE DATABASE IF NOT EXISTS cbrain_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON cbrain_test.* TO 'cbrain'@'%';
