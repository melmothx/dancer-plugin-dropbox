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

The template to use to render the directory listing. If not present or
not set in a hook, an exception is thrown. The file listing structure
is stored into the C<file_listing> key. You can modify the tokens
passed and the template itself at runtime using the
C<dropbox_on_directory_view> view.

An example template (using L<Template::Flute>) could be the following:

=over 4

=item specification

  <specification>
    <list name="files" iterator="file_listing">
      <param name="link" field="location" target="href"/>
      <param name="name" class="link"/>
      <param name="mod_time" class="date"/>
      <param name="size" class="size"/>
      <param name="error" class="error"/>
    </list>
  </specification>

=item template

  <h1>Index of <span class="dirname">$DIR$</span></h1>
  <table>
    <tr>
      <th>Name</th>
      <th>Last Modified</th>
      <th>Size</th>
    </tr>
    <tr class="files">
      <td class="name"><a href="#" class="link">$FILE$</a></td>
      <td class="date">$LAST_MODIFIED$</td>
      <td class="size">$SIZE</td>
      <td class="error">$ERROR$</td>
    </tr>
  </table>

=back

=item layout

The layout to use (defaults to C<main>).

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

The file listing parameters is stored in the token C<file_listing>.
Before sending it to the template, the hook
C<dropbox_on_directory_view> is called, where the template tokens can
be manipulated.




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
        $details->{status} = 403;
        execute_hook dropbox_file_access_denied => $details;
        return _finalize($details);
    }

    debug("Trying to serve $file");
    
    # check if exists
    unless (-e $file and (-f $file or -d $file)) {
        info "file $file not found!";
        $details->{status} = 404;
        execute_hook dropbox_file_not_found => $details;
        return _finalize($details);
    }

    # check if it's a file and send it
    if (-f $file) {
        return send_file($file, system_path => 1);
    }

    # is it a directory?
    my $listing;
    if (-d $file) {
        $listing = autoindex($file, %{ $details->{listing_params} });

        $details->{template} ||= plugin_setting->{template};
        $details->{layout}   ||= plugin_setting->{layout} || "main";

        # add the listing to the template tokens
        $details->{template_tokens}->{file_listing} = $listing;
        # pass it to the hook for editing
        execute_hook dropbox_on_directory_view => $details;

        # last chance to set the template is past.
        die "Missing template!" unless $details->{template};
    }
    else {
        $details->{status} = 404;
    }
    return _finalize($details);
}

sub _finalize {
    my ($details, $exit_value) = @_;
    die "Wrong usage" unless $details;
    my %msgs = (
                403 => 'Access denied',
                404 => 'File not found',
               );

    # if a redirect is set, do that
    if (my $redirect = $details->{redirect}) {
        return redirect $redirect;
    }

    my $status = $details->{status};
    # if status is set, set it
    if ($status) {
        status $status;
    }

    # if a template is set, render it
    if (my $template = $details->{template}) {
        my $layout = { layout => $details->{layout} || 'main' };
        return template $template, $details->{template_tokens}, $layout;
    }
    elsif ($status && $msgs{$status}) {
        my $msg = $details->{status_message} || $msgs{$status};
        return send_error($msg, $status);
    }
    # nothing to do, the app doesn't want a template rendering
    else {
        return $exit_value;
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
The L<Dancer::Upload> object is stored in the key C<uploaded_file>

=cut

sub dropbox_upload_file {
    my ($self, $user, $filepath, $uploaded) = plugin_args(@_);
    my $target = _dropbox_get_filename($user, $filepath);

    my $details = {
                   user => $user,
                   operation => 'upload_file',
                   filepath => $filepath,
                   file => $target,
                   uploaded_file => $uploaded,
                  };

    execute_hook dropbox_find_file => $details;
    $target = $details->{file};

    my $error;
    if (!$target) {
        $error = "Target directory not provided";
    }
    elsif (! -d $target) {
        $error = "$target is not a directory";
    }
    elsif (! $uploaded) {
        $error = "No upload provided";
    }
    # we use _check_root to be sure it's a decent filename, with no \ or /
    elsif (! _check_root($uploaded->basename)) {
        $error = "Bad filename provided";
    }

    my $exit_value;
    if ($error) {
        $details->{errors} = $error;
        $details->{status} = 403;
        execute_hook dropbox_on_upload_file_failure => $details;
    }
    else {
        my $basename = $uploaded->basename;
        my $targetfile = catfile($target, $basename);
        $exit_value = $uploaded->copy_to($targetfile);
        if ($exit_value) {
            execute_hook dropbox_on_upload_file_success => $details;
        }
        else {
            $details->{errors} = "Failed to copy $basename to target directory";
            execute_hook dropbox_on_upload_file_failure => $details;
        }
    }       
    # copy and return the return value
    return _finalize($details, $exit_value);
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
    my $error;
    if (!$target) {
        $error = "No target directory provided";
    }
    elsif (! -d $target) {
        $error = "$target is not a directory";
    }
    elsif (-e $dirname) {
        $error = "$target exists";
    }
    elsif (! _check_root($dirname)) {
        $error = "Bad target name $dirname";
    }

    my $exit_value;
    if ($error) {
        $details->{errors} = $error;
        execute_hook dropbox_on_create_directory_failure => $details;
    }
    else {
        my $dir_to_create = catdir($target, $dirname);
        my $exit_value = mkdir($dir_to_create, 0770);
        if ($exit_value) {
            execute_hook dropbox_on_create_directory_success => $details;
        }
        else {
            $details->{errors} = "Couldn't create $dir_to_create $!";
            execute_hook dropbox_on_create_directory_failure => $details;
        }
    }
    return _finalize($details, $exit_value);
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

    my $error;
    if (!$target) {
        $error = "No target provided";
    }
    elsif (! -d $target) {
        $error = "Target does not exists";
    }
    elsif (! _check_root($filename)) {
        $error = "Bad filename";
    }

    my $exit_value;
    my $file_to_delete = catfile($target, $filename);

    if ($error) {
        $details->{errors} = $error;
        execute_hook dropbox_on_create_directory_failure => $details;
    }
    else {
        if (-f $file_to_delete) {
            $exit_value = unlink($file_to_delete);
        }
        elsif (-d $file_to_delete) {
            $exit_value = rmdir($file_to_delete);
        }
        if ($exit_value) {
            execute_hook dropbox_on_delete_file_success => $details;
        }
        else {
            $details->{errors} = "Couldn't delete $file_to_delete $!";
            execute_hook dropbox_on_delete_file_failure => $details;
        }
    }
    return _finalize($details, $exit_value);
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
            mkdir($user_root, 0770) or die "Couldn't create $user_root $!";
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
    return unless $listing;
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
register_hook 'dropbox_on_directory_view';

register_hook 'dropbox_on_upload_file_success';
register_hook 'dropbox_on_upload_file_failure';

register_hook 'dropbox_on_delete_file_success';
register_hook 'dropbox_on_delete_file_failure';

register_hook 'dropbox_on_create_directory_success';
register_hook 'dropbox_on_create_directory_failure';

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

However, if the key C<redirect> is present with a value, the template
is ignored and a redirect is issued instead.

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

