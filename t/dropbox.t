#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
use File::Spec::Functions qw/catdir catfile/;
use File::Path qw/make_path/;
use File::Slurp;
use File::Basename qw/basename/;

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


# defines some routes

get '/dropbox/*/' => sub {
    my ($user) = splat;
    return dropbox_send_file($user, "/");
};

get '/dropbox/*/**' => sub {
    my ($user, $filepath) = splat;
    return dropbox_send_file($user, $filepath);
};

post '/dropbox/*/**' => \&manage_uploads;
post '/dropbox/*/' => \&manage_uploads;

sub manage_uploads {
    my ($user, $filepath) = splat;
    if (my $uploaded = upload('upload_file')) {
        warning dropbox_upload_file($user, $filepath, $uploaded);
        
    }
    elsif (my $dirname = param("newdirname")) {
        dropbox_create_directory($user, $filepath, $dirname);
    }
    elsif (my $deletion = param("filedelete")) {
        dropbox_delete_file($user, $filepath, $deletion);
    }
    return redirect request->path;
}


# create the files
make_path catdir($basedir, $username);
die "$basedir couldn't be created" unless -d $basedir;

my $testfile = catfile($basedir, $username, "test.txt");
write_file($testfile, "hello world!\n");

# start testing
plan tests => 9;

response_status_is [ GET => "/dropbox/$username/test.txt" ], 200,
  "Found the test.txt for marco";

response_status_is [ GET => "/dropbox/root/test.txt" ], 404,
  "test.txt not found for root";

response_status_is [ GET => "/dropbox/$username/" ], 200,
  "Found the root for marco";

response_content_like [ GET => "/dropbox/$username/" ],
  qr{>\.\.<.*test\.txt}s,
  "Found the listing for marco";

response_status_is [ GET => "/dropbox/../../$username/test.txt" ], 403,
  "Username looks wrong";

my $data  = 'A test string that will pretend to be file contents.';
my $upfilename = "../../../../../../../tmp/test<em><em>hello.ext";

my $upfile_on_disk = catfile($basedir, $username, basename($upfilename));
# diag "Uploading " . $upfile_on_disk;
if (-f $upfile_on_disk) {
    unlink $upfile_on_disk or die "Couldn't remove $upfile_on_disk";
}

my $nastyupload = dancer_response(POST => "/dropbox/$username/",
				     {
				      files => [{
						 name => 'upload_file',
						 filename => $upfilename, 
						 data => $data,
						}]
				     });

ok((-f $upfile_on_disk), "$upfile_on_disk created");
my $content = read_file($upfile_on_disk);
is ($content, $data, "File transferred ok");

response_content_like [ GET => "/dropbox/$username/" ],
  qr{href="test%3Cem%3E%3Cem%3Ehello\.ext">test%3Cem%3E%3Cem%3Ehello\.ext},
  "index looks fine";

response_status_is $nastyupload, 302, "Nasty upload successful but harmless";

# set logger => "console";

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                               newdirname => "XSS"
                                              }
                                     }], 302, "Response ok";



ok(-d catdir($basedir, $username, "XSS"), "directory created");

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                               newdirname => "../XSS"
                                              }
                                     }], 302, "Response ok";

ok(! -d catdir($basedir, "XSS"), "No traversal for new directories");

write_file(catfile(t => "testfile"), "hello\n");

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                                filedelete => "../../testfile"
                                              }
                                     }], 302, "Response ok";

ok(-f catfile(t => "testfile"), "testfile is still there");

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                                filedelete => "%2e%2e%2ftestfile"
                                              }
                                     }], 302, "Response ok";

ok(-f catfile(t => "testfile"), "testfile is still there");
unlink catfile(t => "testfile"); # don't leave stray files

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                                filedelete => "XSS"
                                              }
                                     }], 302, "Response ok";

ok(! -e catfile($basedir, $username, "XSS"), "directory deleted");

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                                filedelete => "test<em><em>hello.ext"
                                              }
                                     }], 302, "Response ok";

ok(! -e catfile($basedir, $username, "test<em><em>hello.ext"), "file deleted");

response_status_is
  [ POST => "/dropbox/$username/" => {
                                      body => {
                                                filedelete => "test.txt"
                                              }
                                     }], 302, "Response ok";

ok(! -e catfile($basedir, $username, "test.txt"), "file deleted");




