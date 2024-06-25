<?php // Query user names database. Written by Ilya Zverev, licensed WTFPL.
require('config.php');

header('Content-type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
$recent_cache = 'recent.json';
$result = array();
if( isset($_REQUEST['action']) ) {
    $db = new mysqli(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE);
    if ($db->connect_errno) {
        $result['error'] = "Failed to connect to MySQL: (" . $db->connect_errno . ") " . $db->connect_error;
    } else {
        $db->set_charset('utf8mb4');

        $ids = array();
        if( isset($_REQUEST['id']) && preg_match('/^\d+$/', $_REQUEST['id']) ) {
            $ids[] = $_REQUEST['id'];
        }
        elseif( isset($_REQUEST['name']) && strlen($_REQUEST['name']) > 0 ) {
            $res = $db->query('select user_id from whosthat where user_name = \''.$db->escape_string($_REQUEST['name']).'\'');
            while( $row = $res->fetch_row() ) {
                $ids[] = $row[0];
            }
            $res->close();
        }
        elseif( isset($_REQUEST['q']) && strlen($_REQUEST['q']) > 2 ) {
            $res = $db->query('select distinct user_id from whosthat where user_name like \'%'.$db->escape_string($_REQUEST['q']).'%\' order by length(user_name), user_id limit 30');
            while( $row = $res->fetch_row() ) {
                $ids[] = $row[0];
            }
            $res->close();
        }

        $action = $_REQUEST['action'];
        if( $action == 'last' ) { // Last usernames by old name
            foreach( $ids as $id ) {
                $res2 = $db->query("select user_name from whosthat where user_id = $id order by date_last desc limit 1");
                $row = $res2->fetch_row();
                $result[] = $row[0];
                $res2->close(); 
            }

        } elseif( $action == 'info' ) { // Search for user, get all info on each
            foreach( $ids as $id ) {
                $res2 = $db->query("select * from whosthat where user_id = $id order by date_last");
                $u = array();
                while( $row = $res2->fetch_assoc() ) {
                    $u[] = array(
                        'name' => $row['user_name'],
                        'first' => $row['date_first'],
                        'last' => $row['date_last']
                    );
                }
                $res2->close(); 
                $result[] = array(
                    'id' => $id,
                    'names' => $u
                );
            }

        } elseif( $action == 'names' ) { // Get history of username changes
            foreach( $ids as $id ) {
                $res2 = $db->query("select * from whosthat where user_id = $id order by date_last");
                $names = array();
                while( $row = $res2->fetch_assoc() ) {
                    $names[] = $row['user_name'];
                }
                $res2->close();
                $result[] = array( 'id' => $id, 'names' => $names );
            }

        } elseif( $action == 'recent' ) { // Get recent user renames
            // sort users by the second biggest date_last, return 15 results. Cache it.
            if( file_exists($recent_cache) && filesize($recent_cache) > 2 && time() - filemtime($recent_cache) < 600 ) {
                $result = @file_get_contents($recent_cache);
            } else {
                $sql = 'select * from whosthat w inner join (SELECT user_id, count(1) as cnt, max(date_last) as last FROM whosthat group by user_id having cnt > 1) l on l.user_id = w.user_id where w.date_last != l.last order by w.date_last desc limit 15';
                $res2 = $db->query($sql);
                while( $row = $res2->fetch_assoc() ) {
                    $u = array('id' => $row['user_id'], 'date' => $row['date_last'], 'from' => $row['user_name']);
                    $res3 = $db->query('select user_name from whosthat where user_id = '.$row['user_id'].' order by date_last desc limit 1');
                    $row3 = $res3->fetch_row();
                    $u['to'] = $row3[0];
                    $result[] = $u;
                }
                $res2->close();
                @file_put_contents($recent_cache, json_encode($result));
            }
        } else { // Unknown action, return error
            $result['error'] = 'Unknown action';
        }
    }
} else {
    $result['error'] = 'Please specify action';
}
if( is_array($result) )
    $result = json_encode($result);
if( isset($_REQUEST['jsonp']) && strlen($_REQUEST['jsonp']) > 0 )
    $result = $_REQUEST['jsonp'].'('.$result.');';
print $result;
?>
