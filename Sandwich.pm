package Apache::Sandwich;

use strict;
use 5.004;
use mod_perl 1.02;
use Apache::Include ();
use Apache::Constants qw(OK DECLINED DOCUMENT_FOLLOWS);
$Apache::Sandwich::VERSION = (qw$Revision: 1.10 $)[1];

sub handler {
    my($r) = @_;

    #avoid ourselves when Apache::Include->virtual 
    #runs subrequests below
    return DECLINED unless $r->is_main;

    #send headers to the client
    $r->content_type("text/html");
    $r->send_http_header;

    #httpd.conf or .htaccess says:
    #PerlSetVar HEADER 
    my(@header) = split /\s+/, $r->dir_config("HEADER");
    my(@footer) = split /\s+/, $r->dir_config("FOOTER");

    warn "HEADER=", join(",", @header), $/;
    warn "FOOTER=", join(",", @footer), $/;
    #run subrequests to include the uri's
    for my $uri (@header, $r->uri, @footer) {

        my $status = Apache::Include->virtual($uri, $r) if $uri;
	#warn "sandwiching $uri ($status)\n";

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
custom "header" and/or "footer" content to a given uri.

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

=head1 KNOWN BUGS

Headers printed by mod_perl scripts used as a HEADER, FOOTER or
in-the-middle uri need to use CGI.pm version 2.37 or higher or headers
will show up in the final document (browser window).  Suggested
work-around (if you don't want to upgrade CGI.pm):
                                                          
    if($ENV{MOD_PERL} and Apache->request->is_main) {
        #send script headers
	print "Content-type: text/html\n\n";
    }
    else {
       #we're part of a sub-request, don't send headers
    }
                    
=head1 AUTHOR

Doug MacEachern



