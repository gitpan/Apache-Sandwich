#! /usr/local/bin/perl
package Apache::Sandwich;

use strict;
use 5.004;
use mod_perl 1.02;
use Apache::Include ();
use Apache::Constants qw(OK DECLINED NOT_FOUND M_GET DOCUMENT_FOLLOWS);
$Apache::Sandwich::VERSION = do {my @r=(q$Revision: 2.1 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r};

use vars qw($Debug);
$Debug ||= 0;

sub handler {
    my($r) = @_;

    local (*F);

    # only works for GET method
    return DECLINED unless ($r->method_number() == M_GET);

    my $subr = $r->lookup_uri($r->uri);
    my $fileName = $subr->filename;

    return DECLINED unless -T $fileName;

    open(F,$fileName) or return NOT_FOUND; # file not found

    #httpd.conf or .htaccess says:
    #PerlSetVar HEADER 
    my(@header) = split /\s+/, $r->dir_config("HEADER");
    my(@footer) = split /\s+/, $r->dir_config("FOOTER");

    warn "HEADER=", join(",", @header), $/ if $Debug;
    warn "FOOTER=", join(",", @footer), $/ if $Debug;

    #send headers to the client
    $r->content_type("text/html");
    $r->send_http_header;

    #run subrequests to include the HEADER uri's
    foreach (@header) {
        my $status = Apache::Include->virtual($_, $r) if $_;
	warn "sandwiching $_ ($status)\n" if $Debug;
	#bail if we fail!
	return $status unless $status == DOCUMENT_FOLLOWS; 
    }

    $r->send_fd('F');		# send the actual file
    close(F);

    #run subrequests to include the FOOTER uri's
    foreach (@footer) {
        my $status = Apache::Include->virtual($_, $r) if $_;
	warn "sandwiching $_ ($status)\n" if $Debug;
	#bail if we fail!
	return $status unless $status == DOCUMENT_FOLLOWS; 
    }

    return OK;
}

1;

__END__

=head1 NAME 

Apache::Sandwich - Layered document (sandwich) maker

=head1 SYNOPSIS

 SetHandler  perl-script
 PerlHandler Apache::Sandwich

=head1 DESCRIPTION

The B<Apache::Sandwich> module allows you to add a per-directory
custom "header" and/or "footer" content to a given uri.  Only works
with "GET" requests for static content HTML or text files.  Output of
combined parts is forced to I<text/html>.

Here's a configuration example:

 #in httpd.conf or .htaccess

 <Location /foo>
  #any request for /foo and it's document tree
  #are run through our Apache::Sandwich::handler
  SetHandler  perl-script
  PerlHandler Apache::Sandwich

  #we send this file first
  PerlSetVar HEADER /my_header.html

  #requested uri (e.g. /foo/index.html) is sent in the middle

  #we send output of this mod_perl script last  
  PerlSetVar FOOTER /perl/footer.pl
 </Location>

With the above example, one must be careful not to put graphics within
the same directory, otherwise they will be Sandwiched also.

Here's another example which only Sandwiches the files we want (using
Apache 1.3 syntax):

 # filter *.brc files through Sandwich maker, but define
 # HEADER/FOOTER per section below
 
 <FilesMatch "\.brc$">
  SetHandler  perl-script
  PerlHandler Apache::Sandwich
 </FilesMatch>
 
 # now specify the header and footer for each major section
 #
 <Location /misc>
   PerlSetVar HEADER /misc/HEADER.shtml ADS.shtml
   PerlSetVar FOOTER /misc/FOOTER.html
 </Location>
 
 <Location /getting_started>
   PerlSetVar HEADER /getting_started/HEADER.shtml ADS.shtml
   PerlSetVar FOOTER /misc/FOOTER.html
 </Location>

Note that in this example, the file F<ADS.shtml> is included from the
same directory as the requested file.

The files referenced in the HEADER and FOOTER variables are fetched
using the "GET" method and may produce dynamically generated text.

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

The sandwiched file must be a plain static HTML or text file.  If
someone knows how to call an alternate handler for the file, please
contribute the patches!

=head1 AUTHOR

Doug MacEachern.  Modifications and cleanup by Vivek Khera.

=cut
