#!perl

use strict;
use warnings;
use Test::More tests => 9;

use File::Spec::Functions qw/catfile catdir/;

use lib catdir( 't', 'lib' );

use Dancer qw/:tests/;

my $basedir = catdir(qw/t redirections/);

set views => catdir(t => 'views');

set template => 'simple';


set log => 'debug';
set logger => 'capture';
set template => 'template_flute';

set plugins => {
                Dropbox => {
                            basedir => $basedir,
                            autocreate_root => 1,
                            template => 'autoindex',
                           }
               };

mkdir $basedir unless -d $basedir;

# set the hook which redirect everything to /

hook dropbox_find_file => sub {
    my $stash = shift;
    debug "In the dropbox_find_file hook!";
};

hook dropbox_on_directory_view => sub {
    my $stash = shift;
    $stash->{status} = 403;
    $stash->{template} = 'generic';
    $stash->{template_tokens}->{message} = 'View denied';
};

hook dropbox_file_not_found => sub {
    my $stash = shift;
    $stash->{redirect} = '/dropbox/' . $stash->{user} . '/';
};

hook dropbox_on_upload_file_success => sub {
    my $stash = shift;
    $stash->{template} = 'generic';
    $stash->{template_tokens}->{message} = 'Upload success';
};

hook dropbox_on_upload_file_failure => sub {
    my $stash = shift;
    $stash->{template} = 'generic';
    $stash->{template_tokens}->{message} = 'Upload failed';
};


use MyApp;
use Dancer::Test;

my $resp = dancer_response GET => '/dropbox/marco/ciao.txt';

like read_logs->[0]->{message}, qr/dropbox_find_file hook/;

response_status_is $resp, 302, "GET /dropbox/marco/ciao.txt redirects to /";

response_redirect_location_is $resp, "http://localhost/dropbox/marco/", "redirect location ok";

$resp = dancer_response(POST => '/dropbox/marco/' => {
                                                      files => [{
                                                                 name => 'upload',
                                                                 filename => 'aa.txt',
                                                                 data => 'bbb',
                                                                }],
                                                     });

response_content_like $resp, qr/Upload success/;
ok (-f catfile($basedir, qw/marco aa.txt/));

$resp = dancer_response(POST => '/dropbox/marco/blabla' => {
                                                      files => [{
                                                                 name => 'upload',
                                                                 filename => 'aa.txt',
                                                                 data => 'bbb',
                                                                }],
                                                     });

response_content_like $resp, qr/Upload failed/;
ok (-f catfile($basedir, qw/marco aa.txt/));

$resp = dancer_response( GET => '/dropbox/marco/');

# this is silly, but just as test
response_status_is $resp, 403;
response_content_like $resp, qr/View denied/;

