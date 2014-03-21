#!/usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 21;
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
                            template => 'autoindex',
                           }
               };

set views => catdir(t => 'views');
set log => 'debug';
set logger => 'capture';
set template => 'template_flute';

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
    my $file = $details->{file};
    diag "This is an hook changing to something that does not exist";
    # change the file to a directory
    $details->{file} = catdir($basedir, $username, 'lkasdjfasdf');
};

diag "Testing the 404 hook, changing the filepath to something that doesn't exist";

hook dropbox_file_not_found => sub {
    my $details = shift;
    ok $details->{file},
      "Token $details->{file} exists but it's not found";
    $details->{template} = 'not_found';
    $details->{template_tokens}->{filepath} = $details->{filepath}->[0];
};

$res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 404, "hook modify request to something not found!";
response_content_like $res, qr/My shiny template.*test\.txt/, "Template rendered";


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
    diag "This is the forth hook (deny access checking)";
    # change the file to a directory
    # diag to_dumper($details);
    ok (!exists $details->{file}, "file token doesn't exist any more");
    is $details->{operation}, 'send_file';
};

hook dropbox_file_access_denied => sub {
    my $details = shift;
    $details->{template} = 'denied';
    $details->{template_tokens}->{message} = 'Access denied by app, hook executed';
};

read_logs;

$res = dancer_response(GET => "/dropbox/$username/test.txt");

response_status_is $res, 403,
  "Access denied to test.txt via hook" or diag to_dumper(read_logs);



response_content_like $res,
  qr/In denied template:.*Access denied by app, hook executed/,
  "denied template rendered";


