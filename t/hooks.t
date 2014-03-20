#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 14;
use File::Spec::Functions qw/catdir catfile/;
use File::Path qw/make_path/;
use File::Slurp;
use File::Basename qw/basename/;


use Dancer ":tests";
use Dancer::Plugin::Dropbox;
use Dancer::Test;

my $basedir = catdir(t => "dropbox-hooks");

set plugins => {
                Dropbox => {
                            basedir => $basedir,
                           }
               };

get '/dropbox/*/' => sub {
    my ($user) = splat;
    return dropbox_send_file($user, "/");
};

get '/dropbox/*/**' => sub {
    my ($user, $filepath) = splat;
    return dropbox_send_file($user, $filepath);
};

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


post '/dropbox/*/**' => \&manage_uploads;
post '/dropbox/*/' => \&manage_uploads;

hook dropbox_find_file => sub {
    my $details = shift;
    diag "This is the first hook";
    my $file = $details->{file};
    ok ($file, "The hooks returns the file path: $file");
    ok (-f $file, "File $file exists");
};

my $username = 'marco';
make_path catdir($basedir, $username);

my $testfile = catfile($basedir, $username, "test.txt");
write_file($testfile, "hello world!\n");

my $res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 200,
  "Found the test.txt for marco";

diag "Adding another hook";

hook dropbox_find_file => sub {
    my $details = shift;
    my $file = $details->{file};
    diag "This is the second hook";
    # change the file to a directory
    $details->{file} = catdir($basedir, $username);
};

$res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 200,
  "Found the test.txt for marco";

response_content_like $res, qr/href="test\.txt/, "With the new hook we get content listing";

hook dropbox_find_file => sub {
    my $details = shift;
    diag "This is the third hook (deny access)";
    # change the file to a directory
    debug "Deny access deleting the file from the hashref";
    delete $details->{file};
};

$res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 403,
  "Access denied to test.txt via hook";


hook dropbox_find_file => sub {
    my $details = shift;
    diag "This is the forth hook (deny access)";
    # change the file to a directory
    diag to_dumper($details);
    ok (!exists $details->{file});
};

$res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 403,
  "Access denied to test.txt via hook";
