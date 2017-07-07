#!/usr/bin/perl

use strict;
use warnings;
use CGI;
use DBI;
use DBD::mysql;
use JSON;
use List::Util 1.33 'any';

my $cgi = CGI->new();

# Set database variables
my $platform = "mysql";
my $database = $cgi->param('search_db_name');
my $host = $cgi->param('search_db_host');
my $port = $cgi->param('search_db_port');
my $user = $cgi->param('search_db_user');

# write CGI header
print $cgi->header('application/json');

# Connect to database
my $dsn = "dbi:mysql:$database:$host:$port";
my $dbh = DBI->connect($dsn, $user);

# populate a list
my @names = $cgi->param;
my $list = $cgi->param('list');
if($list){
	if ($list eq 'tables'){
		my $sth = $dbh->prepare(qq{SHOW TABLES});
		$sth->execute();
		my @tables;
		while (my ($table) = $sth->fetchrow_array()){
			if ($table !~ m/(:?multi|_32|_255)$/){
				push @tables,$table;
			}
		}
		print JSON::to_json(\@tables);
	}
	exit;
}

# or autocomplete search terms
my $term = $cgi->param('term');
my $tablename = $cgi->param('table');

# Prepare the queries
my $table_32 = $tablename."_32";
my $table_255 = $tablename."_255";
my $sth1 = $dbh->prepare(qq{SELECT feature_id as id, string as value FROM $table_32 WHERE string LIKE '$term\%' GROUP BY string LIMIT 10;});
my $sth2 = $dbh->prepare(qq{SELECT feature_id as id, string as value, MATCH(string) AGAINST('$term') as relevance FROM $table_255 WHERE MATCH(string) AGAINST('$term') GROUP BY string ORDER BY relevance DESC LIMIT 10;});
my $sth3 = $dbh->prepare(qq{SELECT feature_id as id, string as value FROM $tablename WHERE string LIKE '\%$term\%' GROUP BY string LIMIT 10;});
my @query_output;
my @strings;
my %query_output;

# Execute the first query
$sth1->execute();
while ( my $row = $sth1->fetchrow_hashref ){
    push @strings, lc $row->{'value'};
	#$row->{'value'} = '1.'.$row->{'value'};
    push @query_output, $row;
    $query_output{$row->{'value'}} = 1;
}
if (@query_output < 1){
	# Execute the second query
	$sth2->execute();
	while ( my $row = $sth2->fetchrow_hashref ){
		unless ($query_output{$row->{'value'}}){
	    	push @strings, lc $row->{'value'};
    		#$row->{'value'} = '2.'.$row->{'value'};
    		push @query_output, $row;
	   	 	$query_output{$row->{'value'}} = 1;
    	}
	}
	my $match = any { /$term/i } @strings;
	if (@query_output < 1 || !$match){
		# Execute the third query
		$sth3->execute();
		while ( my $row = $sth3->fetchrow_hashref ){
			unless ($query_output{$row->{'value'}}){
	    		push @strings, lc $row->{'value'};
		    	#$row->{'value'} = '3.'.$row->{'value'};
	    		push @query_output, $row;
		    }
		}
	}

}

$dbh->disconnect();

# Print results as JSON
print JSON::to_json(\@query_output);
