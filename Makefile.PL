#! /usr/local/bin/perl
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'	=> 'Apache::Sandwich',
	      'VERSION_FROM' => 'Sandwich.pm', # finds $VERSION
	      dist => {
		       PREOP => 'pod2text Sandwich.pm > README',
		       SUFFIX => 'gz',
		       COMPRESS => 'gzip -9',
		      }
	     );
