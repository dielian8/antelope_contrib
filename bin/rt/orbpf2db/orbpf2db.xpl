require "getopts.pl" ;
use Datascope;
use orb;
 
# Kent Lindquist
# Lindquist Consulting
# orbpf2db
# July, 2003

sub database_prep {
	my( $wantschema ) = pop( @_ );
	my( $dbname ) = pop( @_ );

	if( ! defined( @db ) ) { 

		if( -e "$dbname" ) {
			
			@db = dbopen( $dbname, "r+" );

			$haveschema = dbquery( @db, dbSCHEMA_NAME );

			if( $haveschema ne $wantschema ) {

				elog_complain( "Wrong schema in '$dbname' for current packet " .
					       "(have $haveschema, want $wantschema)\n" );
				return 0;

			} else {

				return 1;
			}

		} else {
			
			dbcreate( $dbname, $wantschema );

			@db = dbopen( $dbname, "r+" );
		}
		
	} else {

		$haveschema = dbquery( @db, dbSCHEMA_NAME );

		if( $haveschema ne $wantschema ) {

			elog_complain( "Wrong schema in '$dbname' for current packet " .
				       "(have $haveschema, want $wantschema)\n" );
			return 0;

		} else {

			return 1;
		}
	}
}

sub reopen_database {

	my( $dbname ) = dbquery( @db, dbDATABASE_NAME );

	dbclose( @db );

	system( "dbcrunch $dbname" );

	@db = dbopen( $dbname, "r+" );

	return;
}

$Pf = "orbpf2db.pf";
$match = ".*/pf/orbstat";
$write_mode = "overwrite";
$pktid = 0;
$time = -9999999999.999;

if ( ! &Getopts('s:w:f:p:m:vV') || @ARGV != 2 ) { 

    	die ( "Usage: orbpf2db [-vV] [-p pffile] [-m match] [-f from] [-w mode] orb database\n" ) ; 

} else {
	
	$orbname = $ARGV[0];
	$dbname = $ARGV[1];
}

if( $opt_V ) {
	
	$opt_v++;
}

if( $opt_p ) {
	
	$Pf = $opt_p;
}

%trans = %{pfget( $Pf, "translations" )};

if( $opt_m ) {
	
	$match = $opt_m;
}

if( $opt_w ) {

	if( $opt_w =~ /^(overwrite|add)$/ ) {
		
		$write_mode = $opt_w;

	} else {
		
		die( "-w mode must be 'overwrite' or 'add'\n" );
	}
}

$orb = orbopen( $orbname, "r&" );

if( $orb < 0 ) {

	die( "Failed to open orb '$orbname' for reading\n" );
}

orbselect( $orb, $match );

if( $opt_f && ( ! $opt_s || ! -e "$opt_s" ) ) {
	
	orbposition( $orb, $opt_f );
	$pktid = orbtell( $orb );

} elsif( $opt_f ) {

	print STDERR "Ignoring -f in favor of existing state-file\n";
}

if( $opt_s ) {

	$stop = 0;
	exhume( $opt_s, \$stop, 15 );
	orbresurrect( $orb, \$pktid, \$time  );
	orbseek( $orb, "$pktid" );
}

for( ; $stop == 0 ; ) {

	($pktid, $srcname, $time, $packet, $nbytes) = orbreap( $orb );

	if( $opt_s ) {

		bury();
	}

	($result, $pkt) = unstuffPkt( $srcname, $time, $packet, $nbytes ); 

	if( $result ne "Pkt_pf" ) {
		if( $opt_v ) {
			printf "Received a $result, skipping\n";
		}
		next;
	}

	if( $opt_V ) {

		printf "Received a parameter-file '$srcname':\n" . 
		pf2string( $pkt->pf ) . "\n\n";
	}

	( $key ) = grep( "$srcname", keys( %trans ) );
	
	next if( ! defined( $key ) );

	$schema = $trans{$key}{"schema"};

	next unless database_prep( $dbname, $schema );

	%clean = %{$trans{$key}{"clean"}};

	foreach $cleantable ( keys( %clean ) ) {

		@dbscratch = dblookup( @db, "", "$cleantable", "", "dbSCRATCH" );
		@dbtable = dblookup( @db, "", "$cleantable", "", "dbALL" );

		%fieldmap = %{$trans{$key}{"clean"}{$cleantable}};

		@matchfields = ();
		foreach $field ( keys( %fieldmap ) ) {

			$pattern = $fieldmap{$field};

			if( $pattern =~ /^TIME:/ ) {

				$pattern =~ s/^TIME://;
				$value = pfget( $pkt->pf, $pattern );
				$value =~ s/^\s*([\d\-.]+).*/$1/;

			} elsif( $pattern =~ /^BOOLEAN:/ ) {

				$pattern =~ s/^BOOLEAN://;
				$value = pfget_boolean( $pkt->pf, $pattern );

			} else {
		
				$value = pfget( $pkt->pf, $pattern );
			}

			dbputv( @dbscratch, "$field", $value );

			push( @matchfields, $field );
		}

		$hookname = "hook_clean_$dbtable[0]_$cleantable";
		@records = dbmatches( @dbscratch, @dbtable, 
						$hookname, @matchfields  );

		foreach $record ( @records ) {
			
			$dbtable[3] = $record;

			dbmark( @dbtable );
		}

	}

	reopen_database();

	%tables = %{$trans{$key}{"tables"}};

	foreach $table ( keys( %tables ) ) {

		@dbscratch = dblookup( @db, "", "$table", "", "dbSCRATCH" );
		@dbtable = dblookup( @db, "", "$table", "", "dbALL" );

		%fieldmap = %{$trans{$key}{"tables"}{$table}};

		if( defined( $fieldmap{FOREACH} ) ) {

			$structref = pfget( $pkt->pf, $fieldmap{FOREACH} );

			next if( ! defined( $structref ) );

			if( ref( $structref ) eq "HASH" ) {

				%arrays = %$structref;
				@mykeys = keys( %arrays );

			} elsif( ref( $structref ) eq "ARRAY" ) {

				@mykeys = 0..$#{$structref};

			} else {
				printf STDERR
				  "Problem with FOREACH for table '$table'\n";
				next;
			}

			foreach $key ( @mykeys ) {

				foreach $field ( keys( %fieldmap ) ) {

					next if( $field eq "FOREACH" );

					$pattern = $fieldmap{$field};
					
					if( $pattern =~ /^FOREACH$/ ) {
						
						$value = $key;

					} elsif( $pattern =~ /^TIME:/ ) {

						$pattern =~ s/FOREACH/$key/;
						$pattern =~ s/^TIME://;
						$value = pfget( $pkt->pf, $pattern );
						$value =~ s/^\s*([\d\-.]+).*/$1/;

					} elsif( $pattern =~ /^BOOLEAN:/ ) {

						$pattern =~ s/FOREACH/$key/;
						$pattern =~ s/^BOOLEAN://;
						$value = pfget_boolean( $pkt->pf, $pattern );

					} else {

						$pattern =~ s/FOREACH/$key/;
						$value = pfget( $pkt->pf, $pattern );
					}

					dbputv( @dbscratch, "$field", $value );
				}

				if( $write_mode eq "add" ) {
	
					dbadd( @dbtable );

				} elsif( $write_mode eq "overwrite" ) {
	
					$hookname = "hook__$dbtable[0]_$table";	
					@matchfields = dbquery( @dbtable, dbPRIMARY_KEY );
					@records = dbmatches( @dbscratch, @dbtable, $hookname, @matchfields );	
					@records = sort {$a <=> $b} @records;
					if( ! defined( @records ) || 
					    ( $recno = shift( @records ) ) !~ /^\d+$/ ) {
	
						dbadd( @dbtable );
	
					} else {
	
						@dbreplace = @dbtable;
						$dbreplace[3] = $recno;
						dbput( @dbreplace );
					}
				}
			}

		} else {
			
			foreach $field ( keys( %fieldmap ) ) {

				$pattern = $fieldmap{$field};

				if( $pattern =~ /^TIME:/ ) {

					$pattern =~ s/^TIME://;
					$value = pfget( $pkt->pf, $pattern );
					$value =~ s/^\s*([\d\-.]+).*/$1/;

				} elsif( $pattern =~ /^BOOLEAN:/ ) {

					$pattern =~ s/^BOOLEAN://;
					$value = pfget_boolean( $pkt->pf, $pattern );

				} else {
			
					$value = pfget( $pkt->pf, $pattern );
				}

				dbputv( @dbscratch, "$field", $value );
			}

			if( $write_mode eq "add" ) {
				
				dbadd( @dbtable );
			
			} elsif( $write_mode eq "overwrite" ) {

				$hookname = "hook_$dbtable[0]_$table";
				@matchfields = dbquery( @dbtable, dbPRIMARY_KEY );
				@records = dbmatches( @dbscratch, @dbtable, $hookname, @matchfields );

				if( ! defined( @records ) || scalar( @records ) < 1 ) {
	
					dbadd( @dbtable );
	
				} else {

					@records = sort {$a <=> $b} @records;
					@dbreplace = @dbtable;
					$dbreplace[3] = shift( @records );
					dbput( @dbreplace );
				}
			}
		}
	}
}
