display('Running dbexample_pfwrite')

echo on

pf = dbpf( 'rtexec' );

pfwrite( pf,'/tmp/rtexec_copy.pf' )

echo off
