display('Running dbexample_dbread_view')

dbexample_get_demodb_path;

echo on

% Make a copy of the tables we need so we don't corrupt the 
% demo database:

output_dbname = ['/tmp/newdb_' getenv('USER')]
unix( ['cp ' demodb_path '.arrival ' output_dbname '.arrival'] );
unix( ['cp ' demodb_path '.wfdisc ' output_dbname '.wfdisc'] );

db = dbopen( output_dbname,'r' );

dbarrival=dblookup_table( db,'arrival' );
dbwfdisc=dblookup_table( db,'wfdisc' );
db=dbjoin( dbarrival,dbwfdisc );
dbsave_view( db );
viewname = dbquery( db, 'dbTABLE_NAME' );
dbclose( db );

db = dbread_view( [output_dbname '.' viewname], 'myview' )

nrecs = dbnrecs( db )

dbclose( db );

unix( ['/bin/rm -f ' output_dbname '*'] );

echo off
