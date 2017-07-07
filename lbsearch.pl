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

# search terms
my $term = $cgi->param('term');
my $tablename = $cgi->param('table') || 'multi';
warn $term;
warn $tablename;
my $page_size = $cgi->param('page_size') || 10;
my $feature_type = $cgi->param('feature_type') || undef;
my $count = $cgi->param('count') || undef;
my $offset = $cgi->param('offset') ? $cgi->param('offset') -1 : 0;
my $page = $offset / $page_size + 1;
$term =~ s/\*/\%/g;
my @coords;
if ($term =~ m/(.+):(\d+)-(\d+)\%*$/){
  @coords = ($2,$3);
  $term = $1;
}

# Prepare the queries
my %query;
$query{'count'} = "SELECT COUNT(string) FROM $tablename WHERE string LIKE '$term' GROUP BY core_id";
#$query{'results'} = "SELECT core_id,string,feature_type,production_name,string_type FROM $tablename WHERE string LIKE '$term' GROUP BY core_id";
$query{'results'} = "SELECT core_id,feature_type,production_name FROM $tablename WHERE string LIKE '$term' GROUP BY core_id";
$query{'detail'} = "SELECT string,string_type,detail FROM $tablename WHERE core_id = ? AND feature_type = ?";
if ($feature_type){
	$query{'count'} =~ s/WHERE/WHERE feature_type = '$feature_type'/;
	$query{'results'} =~ s/WHERE/WHERE feature_type = '$feature_type'/;
}
if ($tablename eq 'multi'){
	$query{'count'} .= ",production_name";
	$query{'results'} .= ",production_name";
}



$query{'results'} .= " LIMIT $page_size OFFSET $offset";

my $sth_count = $dbh->prepare($query{'count'});
my $sth = $dbh->prepare($query{'results'});
my $sth_detail;
$sth_detail = $dbh->prepare($query{'detail'}) unless $tablename eq 'multi';

# Execute the query
$sth->execute();
my @query_output;
while ( my $row = $sth->fetchrow_hashref ){
	my %output;
	if ($tablename eq 'multi'){
		my $pname = $row->{'production_name'};
		$pname =~ s/^'//;
		$pname =~ s/'$//;
		my $q = $query{'detail'};
		$q =~ s/multi/$pname/;
		$sth_detail = $dbh->prepare($q);
	}
	$sth_detail->execute($row->{'core_id'},$row->{'feature_type'});
	my %strings;
	while ( my $ref = $sth_detail->fetchrow_hashref ){
		push @{$strings{$ref->{string_type}}},$ref;
	}

	if ($row->{'feature_type'} eq 'species'){
	  $output{'species'}->{'production_name'} = $row->{'production_name'};
	}
	if ($row->{'feature_type'} eq 'seq_region'){
	    $output{'seq_region'}->{'production_name'} = $row->{'production_name'};
		$output{'seq_region'}->{'name'} = $strings{'seq_region.name'}[0]->{string};
		$output{'seq_region'}->{'seq_length'} = $strings{'seq_region.name'}[0]->{detail};
		@coords = (1,$strings{'seq_region.name'}[0]->{detail}) if !@coords;
		$output{'seq_region'}->{'coords'} = \@coords;
		if ($strings{'seq_region_synonym.synonym'}){
			for (my $i = 0; $i < @{$strings{'seq_region_synonym.synonym'}}; $i++){
				push @{$output{'seq_region'}->{'synonyms'}},$strings{'seq_region_synonym.synonym'}[$i]->{string};
			}
		}
	}
	if ($row->{'feature_type'} eq 'gene'){
	    $output{'gene'}->{'production_name'} = $row->{'production_name'};
		$output{'gene'}->{'stable_id'} = $strings{'gene.stable_id'}[0]->{string};
		$output{'gene'}->{'location'} = $strings{'gene.stable_id'}[0]->{detail};
		$output{'gene'}->{'description'} = $strings{'gene.description'}[0]->{string} if $strings{'gene.description'};
		if ($strings{'gene.xref.dbprimary_acc'}){
			my %xrefs;
			my %dbs;
			my %log;
			for (my $i = 0; $i < @{$strings{'gene.xref.dbprimary_acc'}}; $i++){
				$dbs{$strings{'gene.xref.dbprimary_acc'}[$i]->{string}} = $strings{'gene.xref.dbprimary_acc'}[$i]->{detail};
				$xrefs{$strings{'gene.xref.dbprimary_acc'}[$i]->{string}}{'dbprimary_acc'} = $strings{'gene.xref.dbprimary_acc'}[$i]->{string};
				$xrefs{$strings{'gene.xref.dbprimary_acc'}[$i]->{string}}{'display_label'} = $strings{'gene.xref.dbprimary_acc'}[$i]->{string};
			}
			if ($strings{'gene.xref.display_label'}){
				for (my $i = 0; $i < @{$strings{'gene.xref.display_label'}}; $i++){
					$xrefs{$strings{'gene.xref.display_label'}[$i]->{detail}}{'display_label'} = $strings{'gene.xref.display_label'}[$i]->{string};
				}
			}
			if ($strings{'gene.xref.description'}){
				for (my $i = 0; $i < @{$strings{'gene.xref.description'}}; $i++){
					$xrefs{$strings{'gene.xref.description'}[$i]->{detail}}{'description'} = $strings{'gene.xref.description'}[$i]->{string};
				}
			}
			if ($strings{'gene.xref.external_synonym'}){
				for (my $i = 0; $i < @{$strings{'gene.xref.external_synonym'}}; $i++){
					push @{$xrefs{$strings{'gene.xref.external_synonym'}[$i]->{detail}}{'synonym'}},$strings{'gene.xref.external_synonym'}[$i]->{string};
				}
			}
			foreach my $acc (keys %dbs){
				next if $log{$acc};
				push @{$output{'gene'}->{'dbs'}},$dbs{$acc} unless $log{$dbs{$acc}};
				$log{$dbs{$acc}} = 1;
				$log{$acc} = 1;
				$output{'gene'}->{$dbs{$acc}}->{$acc} = $xrefs{$acc};
			}

		}
		if ($strings{'transcript.stable_id'}){
			for (my $i = 0; $i < @{$strings{'transcript.stable_id'}}; $i++){
				push @{$output{'gene'}->{'transcripts'}->{'stable_ids'}},$strings{'transcript.stable_id'}[$i]->{string};
				#$transcripts{$strings{'transcript.stable_id'}[$i]->{string}}{'stable_id'} = $strings{'transcript.stable_id'}[$i]->{string};
			}
			if ($strings{'transcript.description'}){
				for (my $i = 0; $i < @{$strings{'transcript.description'}}; $i++){
					$output{'gene'}->{'transcripts'}->{$strings{'transcript.description'}[$i]->{detail}}->{'description'} = $strings{'transcript.description'}[$i]->{string};
				}
			}
			if ($strings{'transcript.xref.dbprimary_acc'}){
				my %tsc_xrefs;
				my %tsc_dbs;
				my %tsc_log;
				for (my $i = 0; $i < @{$strings{'transcript.xref.dbprimary_acc'}}; $i++){
					$tsc_dbs{$strings{'transcript.xref.dbprimary_acc'}[$i]->{string}} = $strings{'transcript.xref.dbprimary_acc'}[$i]->{detail};
					$tsc_xrefs{$strings{'transcript.xref.dbprimary_acc'}[$i]->{string}}{'dbprimary_acc'} = $strings{'transcript.xref.dbprimary_acc'}[$i]->{string};
					$tsc_xrefs{$strings{'transcript.xref.dbprimary_acc'}[$i]->{string}}{'display_label'} = $strings{'transcript.xref.dbprimary_acc'}[$i]->{string};
				}
				if ($strings{'transcript.xref.display_label'}){
					for (my $i = 0; $i < @{$strings{'transcript.xref.display_label'}}; $i++){
						$tsc_xrefs{$strings{'transcript.xref.display_label'}[$i]->{detail}}{'display_label'} = $strings{'transcript.xref.display_label'}[$i]->{string};
					}
				}
				if ($strings{'transcript.xref.description'}){
					for (my $i = 0; $i < @{$strings{'transcript.xref.description'}}; $i++){
						$tsc_xrefs{$strings{'transcript.xref.description'}[$i]->{detail}}{'description'} = $strings{'transcript.xref.description'}[$i]->{string};
					}
				}
				if ($strings{'transcript.xref.external_synonym'}){
					for (my $i = 0; $i < @{$strings{'transcript.xref.external_synonym'}}; $i++){
						push @{$tsc_xrefs{$strings{'transcript.xref.external_synonym'}[$i]->{detail}}{'synonym'}},$strings{'transcript.xref.external_synonym'}[$i]->{string};
					}
				}
				foreach my $acc (keys %tsc_dbs){
					next if $tsc_log{$acc};
					push @{$output{'gene'}->{'transcripts'}->{'dbs'}},$tsc_dbs{$acc} unless $tsc_log{$tsc_dbs{$acc}};
					$tsc_log{$tsc_dbs{$acc}} = 1;
					$tsc_log{$acc} = 1;
					$output{'gene'}->{'transcripts'}->{$tsc_dbs{$acc}}->{$acc} = $tsc_xrefs{$acc};
				}
			}
		}
		if ($strings{'translation.stable_id'}){
			for (my $i = 0; $i < @{$strings{'translation.stable_id'}}; $i++){
				push @{$output{'gene'}->{'translations'}->{'stable_ids'}},$strings{'translation.stable_id'}[$i]->{string};
				$output{'gene'}->{'translations'}->{$strings{'translation.stable_id'}[$i]->{string}} = $strings{'translation.stable_id'}[$i]->{detail};
			}
			if ($strings{'translation.xref.dbprimary_acc'}){
				my %tsl_xrefs;
				my %tsl_dbs;
				my %tsl_log;
				for (my $i = 0; $i < @{$strings{'translation.xref.dbprimary_acc'}}; $i++){
					$tsl_dbs{$strings{'translation.xref.dbprimary_acc'}[$i]->{string}} = $strings{'translation.xref.dbprimary_acc'}[$i]->{detail};
					$tsl_xrefs{$strings{'translation.xref.dbprimary_acc'}[$i]->{string}}{'dbprimary_acc'} = $strings{'translation.xref.dbprimary_acc'}[$i]->{string};
					$tsl_xrefs{$strings{'translation.xref.dbprimary_acc'}[$i]->{string}}{'display_label'} = $strings{'translation.xref.dbprimary_acc'}[$i]->{string};
				}
				if ($strings{'translation.xref.display_label'}){
					for (my $i = 0; $i < @{$strings{'translation.xref.display_label'}}; $i++){
						$tsl_xrefs{$strings{'translation.xref.display_label'}[$i]->{detail}}{'display_label'} = $strings{'translation.xref.display_label'}[$i]->{string};
					}
				}
				if ($strings{'translation.xref.description'}){
					for (my $i = 0; $i < @{$strings{'translation.xref.description'}}; $i++){
						$tsl_xrefs{$strings{'translation.xref.description'}[$i]->{detail}}{'description'} = $strings{'translation.xref.description'}[$i]->{string};
					}
				}
				if ($strings{'translation.xref.external_synonym'}){
					for (my $i = 0; $i < @{$strings{'translation.xref.external_synonym'}}; $i++){
						push @{$tsl_xrefs{$strings{'translation.xref.external_synonym'}[$i]->{detail}}{'synonym'}},$strings{'translation.xref.external_synonym'}[$i]->{string};
					}
				}
				foreach my $acc (keys %tsl_dbs){
					next if $tsl_log{$acc};
					push @{$output{'gene'}->{'translations'}->{'dbs'}},$tsl_dbs{$acc} unless $tsl_log{$tsl_dbs{$acc}};
					$tsl_log{$tsl_dbs{$acc}} = 1;
					$tsl_log{$acc} = 1;
					$output{'gene'}->{'translations'}->{$tsl_dbs{$acc}}->{$acc} = $tsl_xrefs{$acc};
				}
			}
		}
	}
	push @query_output, \%output;
}

if (!defined $count && @query_output >= $page_size){
	$sth_count->execute();
	while (my ($c) = $sth_count->fetchrow_array()){
		$count += $c;
	}
}
else {
	$count = @query_output + $offset
}
my %hash;
$hash{'results'} = \@query_output;
$hash{'count'} = $count;
$hash{'page'} = $page;

$dbh->disconnect();

# Print results as JSON
print JSON::to_json(\%hash);

__END__

mysql> select distinct string_type from multi;
+-----------------------------------+
| string_type                       |
+-----------------------------------+
| gene.stable_id                    |
| transcript.stable_id              |
| gene.xref.dbprimary_acc           |
| gene.xref.display_label           |
| gene.xref.description             |
| transcript.xref.dbprimary_acc     |
| transcript.xref.display_label     |
| transcript.xref.description       |
| translation.stable_id             |
| translation.xref.dbprimary_acc    |
| translation.xref.display_label    |
| translation.xref.description      |
| gene.description                  |
| gene.xref.external_synonym        |
| translation.xref.external_synonym |
| transcript.description            |
+-----------------------------------+
