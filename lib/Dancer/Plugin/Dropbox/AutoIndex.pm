package Dancer::Plugin::Dropbox::AutoIndex;

use strict;
use warnings;

use Exporter;

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/autoindex/;
our $VERSION = '0.01';

use File::stat;
use DateTime;
use Format::Human::Bytes;
use File::Spec;
use URI::Escape;

=head2 autoindex ($directory, sort_field => "mod_time")

The autoindex function takes as argument a directory and an optional
named sort_field parameter for sorting, and returns a arrayref with
hashrefs with the relevant file information:

        [
          {
            'location' => '../',
            'mod_time' => '08-Apr-2013 12:58',
            'name' => '..',
            'size' => '-'
          },
          {
            'location' => 'test.txt',
            'mod_time' => '08-Apr-2013 15:04',
            'name' => 'test.txt',
            'size' => '13B'
          }
        ];

=cut

sub autoindex {
	my ($directory, %params) = @_;
	my ($name, @files, $st);
        return [] unless -d $directory;
	$params{sort_field} ||= 'name';
		
	opendir(AUTO, $directory);
	while ($name = readdir(AUTO)) {
		my (%file_info, $file_st, $epoch);

		next if $name eq '.';
		
		# more information about the file in question
		if ($file_st = stat(File::Spec->catfile($directory, $name))) {
			$epoch = $file_st->mtime();
			$file_info{mod_time} = DateTime->from_epoch(epoch => $file_st->mtime)->strftime('%d-%b-%Y %H:%M');
		}
		else {
			$file_info{error} = $!;
		}
		eval {
                    # this could fail if there are bytes > 255, so we
                    # encode it.
		    $name = uri_escape_utf8($name);
		};
		next if $@;

		$file_info{name} = $name;
		
		if (-d $file_st) {
			$file_info{location} = "$name/";
			$file_info{size} = '-';
		}
		else {
			$file_info{location} = $name;
			$file_info{size} = Format::Human::Bytes::base2($file_st->size());
		}

		# escape character used for HTML anchors 
		$file_info{location} =~ s/#/%23/g;
		
		push (@files, \%file_info);
	}

	@files = sort {$a->{$params{sort_field}} cmp $b->{$params{sort_field}}} @files;
	return \@files;
}

1;
