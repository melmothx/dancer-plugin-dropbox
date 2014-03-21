#!perl

use strict;
use warnings;
use Test::More;

use File::Spec;

use lib File::Spec->catdir( 't', 'lib' );

use Dancer qw/:tests/;

my $basedir = File::Spec->catdir(qw/t redirections/);

set views => File::Spec->catdir(t => 'views');

set template => 'simple';


set log => 'debug';
set logger => 'capture';
set template => 'simple';

set plugins => {
                Dropbox => {
                            basedir => $basedir,
                            autocreate_root => 1,
                           }
               };

mkdir $basedir unless -d $basedir;

# set the hook which redirect everything to /

hook dropbox_find_file => sub {
    my $hashref = shift;
    debug "In the dropbox_find_file hook!";
};

hook dropbox_file_not_found => sub {
    my $hashref = shift;
    $hashref->{redirect} = '/dropbox/' . $hashref->{user} . '/';
};

use MyApp;
use Dancer::Test;

my $resp = dancer_response GET => '/dropbox/marco/ciao.txt';

like read_logs->[0]->{message}, qr/dropbox_find_file hook/;

response_status_is $resp, 302, "GET /dropbox/marco/ciao.txt redirects to /";

response_redirect_location_is $resp, "http://localhost/dropbox/marco/", "redirect location ok";

done_testing;
