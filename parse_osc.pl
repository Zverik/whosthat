#!/usr/bin/perl

# Parse osm/osc/changeset files and store user names and ids in the database.
# Written by Ilya Zverev, licensed WTFPL.

use strict;
use Getopt::Long;
use File::Basename;
use LWP::Simple;
use IO::Uncompress::Gunzip;
use DBIx::Simple;
use POSIX;
use Cwd qw(abs_path);

my $wget = `/usr/bin/which wget` || 'wget';
$wget =~ s/\s//s;
my $state_file = dirname(abs_path(__FILE__)).'/state.txt';
my $stop_file = abs_path(__FILE__);
$stop_file =~ s/(\.pl|$)/.stop/;
my $help;
my $verbose;
my $filename;
my $url;
my $database;
my $dbhost = 'localhost';
my $user;
my $password;
my $zipped;
my $clear;

GetOptions(#'h|help' => \$help,
           'v|verbose' => \$verbose,
           'i|input=s' => \$filename,
           'z|gzip' => \$zipped,
           'l|url=s' => \$url,
           'd|database=s' => \$database,
           'h|host=s' => \$dbhost,
           'u|user=s' => \$user,
           'p|password=s' => \$password,
           'c|clear' => \$clear,
           's|state=s' => \$state_file,
           'w|wget=s' => \$wget
           ) || usage();

if( $help ) {
  usage();
}

usage("Please specify database and user names") unless $database && $user;
my $db = DBIx::Simple->connect("DBI:mysql:database=$database;host=$dbhost;mysql_enable_utf8=1", $user, $password, {RaiseError => 1});
$db->query("set names 'utf8mb4'") or die "Failed to set utf8 in mysql";
create_table() if $clear;
my $ua = LWP::UserAgent->new();
$ua->env_proxy;

if( $filename ) {
    open FH, "<$filename" or die "Cannot open file $filename: $!";
    my $h = $zipped ? new IO::Uncompress::Gunzip(*FH) : *FH;
    print STDERR $filename.': ' if $verbose;
    process_osc($h);
    close $h;
} elsif( $url ) {
    $url =~ s#^#http://# unless $url =~ m#://#;
    $url =~ s#/$##;
    update_state($url);
} else {
    usage("Please specify either filename or state.txt URL");
}

sub update_state {
    my $state_url = shift;
    my $resp = $ua->get($state_url.'/state.txt');
    die "Cannot download $state_url/state.txt: ".$resp->status_line unless $resp->is_success;
    print STDERR "Reading state from $state_url/state.txt\n" if $verbose;
    $resp->content =~ /sequenceNumber=(\d+)/;
    die "No sequence number in downloaded state.txt" unless $1;
    my $last = $1;

    if( !-f $state_file ) {
        # if state file does not exist, create it with the latest state
        open STATE, ">$state_file" or die "Cannot write to $state_file";
        print STATE "sequenceNumber=$last\n";
        close STATE;
    }

    my $cur = $last;
    open STATE, "<$state_file" or die "Cannot open $state_file";
    while(<STATE>) {
        $cur = $1 if /sequenceNumber=(\d+)/;
    }
    close STATE;
    die "No sequence number in file $state_file" if $cur < 0;
    die "Last state $last is less than DB state $cur" if $cur > $last;
    if( $cur == $last ) {
        print STDERR "Current state is the last, no update needed.\n" if $verbose;
        exit 0;
    }

    print STDERR "Last state $cur, updating to state $last\n" if $verbose;
    for my $state ($cur+1..$last) {
        die "$stop_file found, exiting" if -f $stop_file;
        my $osc_url = $state_url.sprintf("/%03d/%03d/%03d.osc.gz", int($state/1000000), int($state/1000)%1000, $state%1000);
        print STDERR $osc_url.': ' if $verbose;
        open FH, "$wget -q -O- $osc_url|" or die "Failed to open: $!";
        process_osc(new IO::Uncompress::Gunzip(*FH));
        close FH;

        open STATE, ">$state_file" or die "Cannot write to $state_file";
        print STATE "sequenceNumber=$state\n";
        close STATE;
    }
}

sub process_osc {
    my $handle = shift;
    my %users;
    print STDERR "reading..." if $verbose;
    while(<$handle>) {
        if( /^\s*<.+?uid="(\d+)"/ ) {
            my $uid = $1;
            my $user = decode_xml_entities($1) if /user="([^"]+)"/;
            my $time = $1 if /timestamp="(\d\d\d\d-\d\d-\d\d)/;
            $time = $1 if !$time && /created_at="(\d\d\d\d-\d\d-\d\d)/;
            if( $time && $user ) {
                my $k = $user.$uid;
                if( exists $users{$k} ) {
                    my $h = $users{$k};
                    $h->{first} = $time if $time lt $h->{first};
                    $h->{last} = $time if $time gt $h->{last};
                } else {
                    my $h = {};
                    $h->{uid} = $uid;
                    $h->{user} = $user;
                    $h->{first} = $time;
                    $h->{last} = $time;
                    $users{$k} = $h;
                }
            }
        }
    }
    print STDERR scalar(keys %users)." users, writing..." if $verbose;
    my $sql_ch = "insert into whosthat (user_id, user_name, date_first, date_last) values(?,?,?,?) on duplicate key update date_last = greatest(date_last, values(date_last)), date_first = least(date_first, values(date_first))";
    $db->begin;
    eval {
        for my $c (values %users) {
            $db->query($sql_ch, $c->{uid}, $c->{user}, $c->{first}, $c->{last}) or die $db->error;
        }
        $db->commit;
    };
    if( $@ ) {
        my $msg = $@;
        eval { $db->rollback; };
        die "Transaction failed: $msg";
    }
    print STDERR " OK\n" if $verbose;
}

sub decode_xml_entities {
    my $xml = shift;
    $xml =~ s/&quot;/"/g;
    $xml =~ s/&apos;/'/g;
    $xml =~ s/&gt;/>/g;
    $xml =~ s/&lt;/</g;
    $xml =~ s/&amp;/&/g;
    return $xml;
}

sub create_table {
    $db->query("drop table if exists whosthat") or die $db->error;

    my $sql = <<CREAT1;
create table whosthat (
	user_id int unsigned not null,
        user_name varchar(200) not null,
        date_first date not null,
        date_last date not null,

	primary key (user_id, user_name),
	index idx_name (user_name),
        index idx_last (date_last)
) CHARACTER SET utf8mb4
CREAT1
    $db->query($sql) or die $db->error;
    print STDERR "Database tables were recreated.\n" if $verbose;
}

sub usage {
    my ($msg) = @_;
    print STDERR "$msg\n\n" if defined($msg);

    my $prog = basename($0);
    print STDERR << "EOF";
Populate whosthat database.

usage: $prog -i osc_file [-z] -d database -u user [-h host] [-p password] [-v]
       $prog -l url           -d database -u user [-h host] [-p password] [-v]

 -i file      : read a single osmChange file.
 -z           : input file is gzip-compressed.
 -l url       : base replication URL, must have a state file.
 -h host      : DB host.
 -d database  : DB database name.
 -u user      : DB user name.
 -p password  : DB password.
 -s state     : name of state file (default=$state_file).
 -w wget      : full path to wget tool (default=$wget).
 -c           : drop and recreate DB tables.
 -v           : display messages.

EOF
    exit;
}
