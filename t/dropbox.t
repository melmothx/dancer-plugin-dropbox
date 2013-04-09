#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use File::Spec::Functions qw/catdir catfile/;
use File::Path qw/make_path/;
use File::Slurp;

use Dancer ":tests";
use Dancer::Plugin::Dropbox;
use Dancer::Test;

my $basedir = catdir(t => "dropbox-dir");
my $username = 'marco@linuxia.de';

set plugins => {
                Dropbox => {
                            basedir => $basedir
                           }
               };

set logger => "console";


# defines some routes

get '/dropbox/*/' => sub {
    my ($user) = splat;
    return dropbox_send_file($user, "/");
};

get '/dropbox/*/**' => sub {
    my ($user, $filepath) = splat;
    return dropbox_send_file($user, $filepath);
};

# create the files
make_path catdir($basedir, $username);
die "$basedir couldn't be created" unless -d $basedir;

my $testfile = catfile($basedir, $username, "test.txt");
write_file($testfile, "hello world!\n");

# start testing
plan tests => 4;

response_status_is [ GET => "/dropbox/$username/test.txt" ], 200,
  "Found the test.txt for marco";

response_status_is [ GET => "/dropbox/root/test.txt" ], 404,
  "test.txt not found for root";

response_status_is [ GET => "/dropbox/$username/" ], 200,
  "Found the root for marco";

response_content_like [ GET => "/dropbox/$username/" ],
  qr{>\.\.<.*test\.txt}s,
  "Found the listing for marco";

