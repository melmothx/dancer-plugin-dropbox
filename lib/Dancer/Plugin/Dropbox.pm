package Dancer::Plugin::Dropbox;

use 5.010001;
use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin;
use File::Spec::Functions qw/catfile catdir splitdir/;
use Dancer::Plugin::Dropbox::AutoIndex qw/autoindex/;

=head1 NAME

Dancer::Plugin::Dropbox - The great new Dancer::Plugin::Dropbox!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Dancer::Plugin::Dropbox;

    my $foo = Dancer::Plugin::Dropbox->new();
    ...

=cut

sub dropbox_send_file {
    my ($self, @args) = plugin_args(@_);
    # Dancer::Logger::debug(to_dumper(\@args));

    my $basedir = plugin_setting->{basedir} ||
      catdir(config->{appdir}, "dropbox-datadir");

    # preliminary checking
    die "Only two arguments shall be passed to dropbox_send_file_for\n"
      unless scalar(@args) == 2;
    my ($user, $filepath) = @args;
    unless ($user) {
        status 404;
        Dancer::Logger::warning("No user");
        return;
    }
    my @path;
    if (ref($filepath) eq 'ARRAY') {
        @path = @$filepath;
    }
    elsif (ref($filepath) eq '') {
        # it's a single piece, so use that
        push @path, $filepath;
    }
    my $file = catfile($basedir, _get_sane_path($user, @path));
    Dancer::Logger::debug("Trying to serve $file");
    
    # check if exists
    unless (-e $file) {
        status 404;
        return;
    }

    # check if it's a file and send it
    if (-f $file) {
        return send_file($file, system_path => 1);
    }

    # is it a directory?
    if (-d $file) {
        # for now just return the html
        my $listing = autoindex($file);
        Dancer::Logger::debug(to_dumper($listing));
        my $template = plugin_setting->{index_template};
        my $layout = plugin_setting->{index_template_layout} || "main";
        my $token = plugin_setting->{index_template_token}  || "listing";
        if ($template) {
            return template $template => {
                                          $token => $listing
                                         }, { layout => $layout };
        }
        else {
            return _render_index($listing);
        }
        return to_yaml($listing);
    }
    # if it's not a dir, return 404
    status 404;
    return "";
}


sub _get_sane_path {
    my @pathdirs = @_;
    my @realdir;

    # loop over the dirs and search ".."
    foreach my $dir (@pathdirs) {
        next if $dir =~ m!/\\!; # just to avoid bad names

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


register dropbox_send_file => \&dropbox_send_file;


register_plugin;




=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

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
