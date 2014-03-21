package MyApp;

use strict;
use warnings;

use Dancer qw/:syntax/;
use Dancer::Plugin::Dropbox;
use File::Spec;

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
        return dropbox_upload_file($user, $filepath, $uploaded);
    }
    elsif (my $dirname = param("newdirname")) {
        return dropbox_create_directory($user, $filepath, $dirname);
    }
    elsif (my $deletion = param("filedelete")) {
        return dropbox_delete_file($user, $filepath, $deletion);
    }
}


post '/dropbox/*/**' => \&manage_uploads;
post '/dropbox/*/' => \&manage_uploads;

true;
