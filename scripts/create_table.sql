create table if not exists whosthat (
  user_id int unsigned not null,
  user_name varchar(200) not null,
  date_first date not null,
  date_last date not null,

  primary key (user_id, user_name),
  index idx_name (user_name),
  index idx_last (date_last)
) CHARACTER SET utf8mb4;
