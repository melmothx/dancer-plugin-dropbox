package Dancer::Plugin::Dropbox;

use 5.010001;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin;
use File::Spec::Functions qw/catfile catdir splitdir/;
use Dancer::Plugin::Dropbox::AutoIndex qw/autoindex/;

=head1 NAME

Dancer::Plugin::Dropbox - Dancer plugin for dropbox-like applications.

=head1 VERSION

Version 0.00003

B<This release appears to work, but it is in an early stage of
development and testing>. You have been warned.


=cut

our $VERSION = '0.00003';


=head1 SYNOPSIS

In the config:

  plugins:
    Dropbox:
      basedir: 'dropbox-data'
      template: 'dropbox-listing'
      token: index
      autocreate_root: 1
  
In your route:

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
  
  
=head1 Configuration

The configuration keys are as follows:

=over 4

=item basedir

The directory which will be the root of the dropbox users. The
directory must already exist. Defaults to "dropbox-datadir" in the
application directory.

=item template

The template to use. If not present, a minimal embedded template will
be used.

=item layout

The layout to use (defaults to C<main>).

=item token

The token of your template to use (defaults to C<listing>) for the
directory listing.

=item autocreate_root

If set to a true value, the root for the each user will be created on
the first "GET" request, e.g. C<dropbox-data/marco@test.tld/>

Please note that the dropbox file will be left in a subdirectory of
the basedir named with the username, so if you permit usernames with
"/" or "\" or ".." inside the name, the user will never reach its
files, effectively cutting it out.

=back


=head1 Exported keywords

=head2 dropbox_root

The root directory where served files reside. It can be set with the
C<basedir> configuration key and defaults to C<dropbox-datadir>.

=head2 dropbox_send_file ($user, $filepath, \%template_tokens, \%listing_params)

This keyword accepts a list of positional arguments or a single hash
reference. If the given filename exists, it sends it to the client. If
it's a directory, a directory listing is returned.

The first argument is the dropbox user, which is also the subdirectory
of the dropbox directory.

The second argument is the path of the file, as a single string or as
a arrayref, the same you could get from a Dancer's megasplat (C<**>).
If not provided, it will return the root of the user.

The third argument is an hashref with the template tokens for the
directory listing. This will be used only if the path points to a
directory and ignored otherwise. The configuration file should specify
at least the template to use.

  plugins:
    Dropbox:
      basedir: 'dropbox-data'
      template: 'dropbox-listing'
      token: index
  

The fourth argument is an hashref for the autoindex function. See
L<Dancer::Plugin::AutoIndex> for details.

The directory listing will set the template token specified in the
configuration file under C<token>.

The alternate syntax using a hashref is the following:

  dropbox_send_file {
                     user => $username,
                     filepath => $filepath,
                     template_tokens => \%template_tokens,
                     listing_params  => \%listing_params,
                    };

It calls the hook C<dropbox_find_file> where you can manipulate the path.

If the file can't be accessed, it calls the hook
C<dropbox_file_access_denied> (bad names, or the previous hook removed
the C<file> key. If the file can't be found, it calls the hook
C<dropbox_file_not_found>.

=head2 dropbox_ajax_listing ( $user, $path )

Return a hashref with a single key, the real system path file, and
with the value set to the L<Dancer::Plugin::Dropbox::AutoIndex>
arrayref for the directory $path and user $user.

Retur , or undef if it doesn't exist or it is not a directory.

It calls the hook C<dropbox_find_file> before creating the structure,
so you can manipulate the C<file> path if needed.

=cut

sub dropbox_ajax_listing {
    my ($self, @args) = plugin_args(@_);
    my ($user, $filepath) = @args;
    if (!defined $filepath) {
        $filepath = "/";
    }
    my $file = _dropbox_get_filename($user, $filepath);
    my $details = {
                   operation => 'ajax_listing',
                   user => $user,
                   filepath => $filepath,
                   file => $file,
                  };
    execute_hook dropbox_find_file => $details;

    $file = $details->{file};
    return unless ($file and -d $file);
    return { $file => autoindex($file) };
}


sub dropbox_root {
    return plugin_setting->{basedir} || catdir(config->{appdir},
                                               "dropbox-datadir");
}

sub dropbox_send_file {
    my ($self, @args) = plugin_args(@_);
    # Dancer::Logger::debug(to_dumper(\@args));

    my $details = {
                   user => '',
                   operation => 'send_file',
                   filepath => '/',
                   template_tokens => {},
                   listing_params  => {},
                  };

    my ($user, $filepath, $template_tokens, $listing_params);
    # only one parameter and it's an hashref
    if (@args == 1 and (ref($args[0]) eq 'HASH')) {
        my $argsref = shift @args;
        foreach my $k (qw/user filepath template_tokens listing_params/) {
            if (my $v = $argsref->{$k}) {
                $details->{$k} = $v;
            }
        }
    }
    else {
        foreach my $k (qw/user filepath template_tokens listing_params/) {
            if (@args) {
                $details->{$k} = shift @args;
            }
        }
    }

    # compose the real path name
    $details->{file} = _dropbox_get_filename($details->{user},
                                             $details->{filepath});

    # pass the hashref to the hook for manipulation
    execute_hook dropbox_find_file => $details;

    my $file = $details->{file};

    # if we don't find a file, it means the access was denied.
    unless ($file) {
        debug "file not set or deleted by app for " . to_dumper($details);
        # so pass the details to the dropbox_file_access_denied hook,
        # where the app can set the template and the tokens.
        execute_hook dropbox_file_access_denied => $details;

        return _error_handler(403 => $details);
    }

    debug("Trying to serve $file");
    
    # check if exists
    unless (-e $file and (-f $file or -d $file)) {
        info "file $file not found!";
        execute_hook dropbox_file_not_found => $details;
        return _error_handler(404 => $details);
    }

    # check if it's a file and send it
    if (-f $file) {
        return send_file($file, system_path => 1);
    }

    # is it a directory?
    if (-d $file) {
        # for now just return the html
        Dancer::Logger::debug("Creating autoindex for $file");
        my $listing = autoindex($file, %{ $details->{listing_params} });
        # Dancer::Logger::debug(to_dumper($listing));
        my $template = plugin_setting->{template};
        my $layout   = plugin_setting->{layout} || "main";
        my $token    = plugin_setting->{token}  || "listing";
        if ($template) {
            return template $template => {
                                          $token => $listing,
                                          %{ $details->{template_tokens} },
                                         }, { layout => $layout };
        }
        else {
            return _render_index($listing);
        }
    }

    # if it's not a dir, return 404. Shouldn't be reached, anyway. Not
    # a file nor a directory, something is really off ("trying to
    # access a socket or a device?
    return send_error("File not found", 404);
}

sub _error_handler {
    my ($status, $details) = @_;
    die "Wrong usage" unless $status;
    my %msgs = (
                403 => 'Access denied',
                404 => 'File not found',
               );
    die "Wrong usage" unless $msgs{$status};

    # if a template was set, render that, otherwise just send a 403
    if (my $template = $details->{template}) {
        status $status;
        my $layout = { layout => $details->{layout} || 'main' };
        return template $template, $details->{template_tokens}, $layout;
    }
    else {
        return send_error($msgs{$status}, $status);
    }
}


=head2 dropbox_upload_file($user, $filepath, $fileuploaded)

This keyword manage the uploading of a file.

The first argument is the dropbox user, used as root directory.

The second argument is the desired path, a directory which must
exists.

The third argument is the L<Dancer::Request::Upload> object which you
can get with C<upload("param_name")>.

It returns true in case of success, false otherwise.

It calls the hook C<dropbox_find_file> to find the target destination.

=cut

sub dropbox_upload_file {
    my ($self, $user, $filepath, $uploaded) = plugin_args(@_);
    my $target = _dropbox_get_filename($user, $filepath);

    my $details = {
                   user => $user,
                   operation => 'upload_file',
                   filepath => $filepath,
                   file => $target,
                  };

    execute_hook dropbox_find_file => $details;
    $target = $details->{file};

    unless ($target and -d $target) {
        Dancer::Logger::warning "$target is not a directory";
        return;
    }
    return unless $uploaded;

    my $basename = $uploaded->basename;
    Dancer::Logger::debug("Uploading $basename");

    # we use _check_root to be sure it's a decent filename, with no \ or /
    unless (_check_root($basename)) {
        Dancer::Logger::warning("bad filename");
        return;
    }

    # find the target file
    my $targetfile = catfile($target, $basename);
    Dancer::Logger::info("copying the file to $targetfile");

    # copy and return the return value
    return $uploaded->copy_to($targetfile)
}

=head2 dropbox_create_directory($user, $filepath, $dirname);

The keyword creates a new directory on the top of an existing dropbox
directory.

The first argument is the user the directory belongs to in the dropbox
application.

The second argument is the path where the directory should be created.
This is usually retrieved from the route against which the user posts
the request. The directory must already exist.

The third argument is the desired new name. It should constitute a
single directory, so no directory separator is allowed.

It returns true on success, false otherwise.

It calls the hook C<dropbox_find_file> to find the parent directory of
the target directory.

=cut

sub dropbox_create_directory {
    my ($self, $user, $filepath, $dirname) = plugin_args(@_);
    my $target = _dropbox_get_filename($user, $filepath);

    my $details = {
                   user => $user,
                   operation => 'create_directory',
                   filepath => $filepath,
                   file => $target,
                  };

    execute_hook dropbox_find_file => $details;
    $target = $details->{file};

    # the post must happen against a directory
    return unless ($target and -d $target);

    # we can't create a directory over an existing file
    return if (-e $dirname);
    return unless _check_root($dirname);
    Dancer::Logger::info("Trying to create $dirname in $target");
    my $dir_to_create = catdir($target, $dirname);
    return mkdir($dir_to_create, 0700);
}


=head2 dropbox_delete_file($user, $filepath, $filename);

The keyword deletes a file or an empty directory belonging to an
existing dropbox directory.

The first argument is the dropbox user.

The second argument is the parent directory of the target file. This
is usually retrieved from the route against which the user posts the
request.

The third argument is the target to delete. No directory separator is
allowed here.

It returns true on success, false otherwise.

Internally, it uses C<unlink> on files and C<rmdir> on directories.

It calls the hook C<dropbox_find_file> to find the target file or
directory.

=cut


sub dropbox_delete_file {
    my ($self, $user, $filepath, $filename) = plugin_args(@_);
    my $target = _dropbox_get_filename($user, $filepath);

    my $details = {
                   user => $user,
                   operation => 'delete_file',
                   filepath => $filepath,
                   file => $target,
                  };

    execute_hook dropbox_find_file => $details;
    $target = $details->{file};

    return unless ($target and -e $target);
    return unless _check_root($filename);
    Dancer::Logger::info("Requested deletion:" . catfile($target, $filename));
    my $file_to_delete = catfile($target, $filename);
    if (-f $file_to_delete) {
        return unlink($file_to_delete);
    }
    elsif (-d $file_to_delete) {
        return rmdir($file_to_delete);
    }
    return
}

sub _dropbox_get_filename {
    my ($user, $filepath) = @_;

    # if the filepath is not provided, use the root
    $filepath ||= "/";
    my $basedir = dropbox_root;
    # if the app runs without a $basedir, die
    die "$basedir doesn't exist or is not a directory\n" unless -d $basedir;

    unless ($user && _check_root($user)) {
        return undef;
    }

    my $user_root = catdir($basedir, _get_sane_path($user));
    unless (-d $user_root) {
        if (plugin_setting->{autocreate_root}) {
            Dancer::Logger::info("Autocreating root dir for $user: " .
                                 "$user_root");
            mkdir($user_root, 0700) or die "Couldn't create $user_root $!";
        }
        else {
            Dancer::Logger::warning("Directory for $user does not exist and " .
                                    "settings prevent its creation.");
        }
    }

    # if the app required this path

    # get the desired path
    my @path;
    if (ref($filepath) eq 'ARRAY') {
        @path = @$filepath;
    }
    elsif (ref($filepath) eq '') {
        # it's a single piece, so use that
        @path = split(/[\/\\]/, $filepath);
    }
    else {
        die "Wrong usage! the second argument should be an arrayref or a string\n";
    }

    my $file = catfile($basedir, _get_sane_path($user, @path));
    return $file;
}



sub _get_sane_path {
    my @pathdirs = @_;
    my @realdir;

    # loop over the dirs and search ".."
    foreach my $dir (@pathdirs) {
        next if $dir =~ m![\\/\0]!; # just to avoid bad names

	if ($dir eq ".") {
	    # do nothing
	}

	# the tricky case
	elsif ($dir eq "..") {
	    if (@realdir) {
		pop @realdir;
	    }
	}

	# we check with splitdir if the directory can be splat further
	# with the hosting OS logic
	elsif (splitdir($dir) == 1) {
	    push @realdir, $dir;
	}
	else {
	    # bad chunk, ignore
            next;
	}
    }
    return @realdir;
}

# given that the username is the root directory, we want to be on the
# safe side. See if _get_sane_path returns exactly the argument passed.


sub _check_root {
    my $username = shift;
    my ($root) = _get_sane_path($username);
    if ($root and $root eq $username) {
        return 1
    } else {
        return 0
    }
}


# if a template able to handle the arrayref with the listing, we just
# provide a really simple one.

sub _render_index {
    my $listing = shift;
    my @out = (qq{<!doctype html><head><title>Directory Listing</title></head><body><table><tr><th>Name</th><th>Last Modified</th><th>Size</th></tr>});
    foreach my $f (@$listing) {
        push @out, qq{<tr><td><a href="$f->{location}">$f->{name}</a></td><td>$f->{mod_time}</td><td>$f->{size}</td>};
        if ($f->{error}) {
            push @out, qq{<td>$f->{error}</td>};
        }
        push @out, "</tr>";
    }
    push @out, "</table></body></html>";
    return join("", @out);
}

register_hook 'dropbox_find_file';
register_hook 'dropbox_file_not_found';
register_hook 'dropbox_file_access_denied';

=head1 HOOKS

Hooks provide a way for the app to modify the path as seen by the
plugin, and to change the behaviour of the plugin.

=head2 dropbox_find_file

This hook is called for every operation. It's guaranteed to have a
C<file> key, which is the target file or directory, and a C<operation>
key, to get a minimum of introspection. The operation name is the
exported keyword without the C<dropbox_> prefix.

It's not called for C<dropbox_root>.

Deleting the C<file> key has the effect of deny access to the file for
every operation (which in turn, if inside C<dropbox_send_file>, will
call the C<dropbox_file_access_denied> hook).

=head2 dropbox_file_not_found

Called by C<dropbox_send_file> when it gets a valid path, but no file
could be found. Here you can set C<template>, C<layout>, and
C<template_tokens> for the view rendering which is going to be called
by dropbox_send_file. If not template is set, just the error is sent
to the user.

=head2 dropbox_file_access_denied

Exactly like C<dropbox_file_not_found>, but for access denied.

=cut

register dropbox_root => \&dropbox_root;
register dropbox_send_file => \&dropbox_send_file;
register dropbox_ajax_listing => \&dropbox_ajax_listing;
register dropbox_upload_file => \&dropbox_upload_file;
register dropbox_create_directory => \&dropbox_create_directory;
register dropbox_delete_file => \&dropbox_delete_file;

register_plugin;

=head1 AUTHOR

Marco Pessotto, C<< <melmothx at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dancer-plugin-dropbox at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer-Plugin-Dropbox>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer::Plugin::Dropbox


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer-Plugin-Dropbox>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer-Plugin-Dropbox>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer-Plugin-Dropbox>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer-Plugin-Dropbox/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to Stefan Hornburg (Racke) C<racke@linuxia.de> for the initial
code, ideas and support.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Marco Pessotto.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Dancer::Plugin::Dropbox

# Local Variables:
# tab-width: 8
# End:

