#! /usr/local/bin/perl
package Apache::Sandwich;

use strict;
use 5.004;
use mod_perl 1.19;
use Apache ();
use Apache::Include ();
use Apache::Constants qw(OK DECLINED NOT_FOUND M_GET DOCUMENT_FOLLOWS);

use vars qw($Debug $VERSION);
$Debug ||= 0;

BEGIN {
  #must be one line for MakeMaker to work!
  $VERSION = do { my @r=(q$Revision: 2.5 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
}

sub handler {
    my($r) = @_;

    # only works for GET method on main request
    return DECLINED unless ($r->method_number() == M_GET and $r->is_main());

    my $subr = $r->lookup_uri($r->uri);
    my $fileName = $subr->filename;

    return NOT_FOUND unless -f $fileName; # file not found
    return DECLINED unless -T _; # not a text file

    #httpd.conf or .htaccess says:
    #PerlSetVar HEADER 
    my(@header) = split /\s+/, $r->dir_config("HEADER");
    my(@footer) = split /\s+/, $r->dir_config("FOOTER");

    warn "HEADER=", join(",", @header), $/ if $Debug;
    warn "FOOTER=", join(",", @footer), $/ if $Debug;

    #send headers to the client
    $r->content_type("text/html");
    $r->send_http_header;

    return OK if $r->header_only(); # HEAD request, so skip out early!

    #run subrequests to include the HEADER uri's
    foreach (@header) {
        my $status = Apache::Include->virtual($_, $r) if $_;
	warn "sandwiching $_ ($status)\n" if $Debug;
	#bail if we fail!
	return $status unless $status == DOCUMENT_FOLLOWS; 
    }

    # run subrequest using the specified handler (or default handler)
    # for the main document.
    my $shandler = $r->dir_config('SandwichHandler') || 'default-handler';
    $subr->handler($shandler);
    $subr->args($r->args);	# pass along query string if there is one.
    $subr->run;
    warn "sandwiched main file with $shandler\n" if $Debug;
    return $subr->status unless $subr->status == DOCUMENT_FOLLOWS;

    #run subrequests to include the FOOTER uri's
    foreach (@footer) {
        my $status = Apache::Include->virtual($_, $r) if $_;
	warn "sandwiching $_ ($status)\n" if $Debug;
	#bail if we fail!
	return $status unless $status == DOCUMENT_FOLLOWS; 
    }

    return OK;
}

# insert header/footer parts for mod_perl programs
# MUST RUN UNDER mod_perl ENVIRONMENT.
#
# $which is one of "HEADER" or "FOOTER".
# Use PerlSetVar in httpd.conf to set these values.
sub insert_parts ($) {
  my ($which) = @_;

  my $r = Apache->request;

  my(@parts) = split /\s+/, $r->dir_config($which);
  for my $uri (@parts) {
    warn("inserting $uri " . $r->method() . "\n") if $Debug;
    my $status = Apache::Include->virtual($uri, $r) if $uri;

    #bail if we fail!
    return $status unless $status == DOCUMENT_FOLLOWS; 
  }

  return 0;
}

1;

__END__

=head1 NAME 

Apache::Sandwich - Layered document (sandwich) maker

=head1 SYNOPSIS

 SetHandler  perl-script
 PerlHandler Apache::Sandwich
 PerlSetVar SandwichHandler default-handler

=head1 DESCRIPTION

The B<Apache::Sandwich> module allows you to add a per-directory
custom "header" and/or "footer" content to a given uri.  Only works
with "GET" requests.  Output of combined parts is forced to
I<text/html>.  The handler for the sandwiched document is specified by
the SandwichHandler configuration variable.  If it is not set,
"default-handler" is used.

The basic concept is that the concatenation of the HEADER and FOOTER
parts with the sandwiched file inbetween constitute a complete valid
HTML document.

Here's a configuration example:

 #in httpd.conf or .htaccess

 <Location /foo>
  #any request for /foo and it's document tree
  #are run through our Apache::Sandwich::handler
  SetHandler  perl-script
  PerlHandler Apache::Sandwich

  #we send this file first
  PerlSetVar HEADER "/my_header.html"

  #requested uri (e.g. /foo/index.html) is sent in the middle

  #we send output of this mod_perl script last  
  PerlSetVar FOOTER "/perl/footer.pl"
 </Location>

With the above example, one must be careful not to put graphics within
the same directory, otherwise they will be Sandwiched also.

Here's another example which only Sandwiches the files we want (using
Apache 1.3 syntax).  In this example, all *.brc files are sandwiched
using the defined HEADER and FOOTER parts, with the file itself
assumed to be a plain text file (or static HTML file).  All *.sbrc
files are similarly sandwiched, except that the file itself is assumed
to be an "shtml" file, i.e., it is given to the SSI handler for server
side includes to be processed.

 # filter *.brc files through Sandwich maker, but define
 # HEADER/FOOTER per section below
 
 <FilesMatch "\.brc$">
  SetHandler  perl-script
  PerlHandler Apache::Sandwich
 </FilesMatch>
 
 <FilesMatch "\.sbrc$">
  SetHandler  perl-script
  PerlHandler Apache::Sandwich
  PerlSetVar SandwichHandler server-parsed
 </FilesMatch>
 
 # now specify the header and footer for each major section
 #
 <Location /misc>
   PerlSetVar HEADER "/misc/HEADER.shtml ADS.shtml"
   PerlSetVar FOOTER "/misc/FOOTER.html"
 </Location>
 
 <Location /getting_started>
   PerlSetVar HEADER "/getting_started/HEADER.shtml ADS.shtml"
   PerlSetVar FOOTER "/misc/FOOTER.html"
 </Location>

Note that in this example, the file F<ADS.shtml> is included from the
same directory as the requested file.

The files referenced in the HEADER and FOOTER variables are fetched
using the "GET" method and may be of any type file the server can process.

=head2 Sandwiching mod_perl Programs

The helper function insert_parts() can be used to make your CGI programs look like the rest of your pages.  A simple script would be:

 #! /usr/local/bin/perl
 use strict;

 use CGI;
 use Apache::Sandwich;

 use vars qw($query);

 $query = new CGI or die "Something failed";

 print $query->header();
 Apache::Sandwich::insert_parts('HEADER');

 print $query->p("Hello, world!");

 Apache::Sandwich::insert_parts('FOOTER');

=head1 KNOWN BUGS

Headers printed by mod_perl scripts used as a HEADER, FOOTER or
in-the-middle uri need to use CGI.pm version 2.37 or higher or headers
will show up in the final document (browser window).  Suggested
work-around (if you don't want to upgrade CGI.pm):

 if($ENV{MOD_PERL} and Apache->request->is_main) {
    #send script headers
    print "Content-type: text/html\n\n";
 } else {
    #we're part of a sub-request, don't send headers
 }

Setting $Apache::Sandwich::Debug to 1 will log debugging information
into the Apache ErrorLog.

=head1 AUTHOR

Doug MacEachern.  Modifications and cleanup by Vivek Khera.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
