# OSM User Names Database

This is a very simple database with a web interface that records all username
changes in OpenStreetMap.

## Installation

There is a `parse_osc.pl` script. If you run it with `-c` key, it will create
a table in a specified database. To populate that database, you would need
to parse every replication diff since the dawn of the OSM (the latest changeset
dump won't do: it contains only the latest user names). After that just
set up hourly replication. Parameters of the script are identical to the
similar named one in [WHODIDIT](https://github.com/Zverik/whodidit) project.

You can download database backup [here](http://whosthat.osmz.ru/whosthat.tgz).
It includes a `state.txt` file to put into `scripts/` and a mysql database
dump. The file is updated weekly:
replication diffs are processed very fast, so there's no need to do it more often.

## API

There is an API at `http://textual.ru/whosthat/whosthat.php`. It returns JSON
or JSONP (if you specify `jsonp=<name>` parameter). It has following actions:

  * `action=last`: returns the last username for specified users.
    It's an array of strings.
  * `action=names`: returns all names for specified users, sorted by date.
    It's an array of hashes: `id` for user id and `names` for an array of user names.
  * `action=info`: returns detailed information on name changes for specified users.
    It's an array of hashes: `id` and `names`, the latter contains array of hashes
    with `name` for user name, `first` for the first spotted usage in database
    and `last` for the last one.
  * `action=recent`: returns 15 last renamings.
    It's an array of hashes with `id`, `date`, `from` and `to` keys.
  * `action=refresh`: returns current username for a specified user ID directly
    from OSM API and updates the database. It's an array with a single string.

To specify users, use one of those parameters:

  * `id=<user_id>`: query by user id.
  * `name=<user_name>`: query by user name. Note that there can be several matches.
  * `q=<query_string>`: search all users whose name matches the query string.

## License

All this is written by Ilya Zverev and licensed WTFPL: do whatever you want with it.

