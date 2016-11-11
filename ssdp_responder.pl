#! /usr/bin/env perl

use strict;
use warnings;

use IO::Socket::Multicast;
use Data::UUID;
use POSIX qw(strftime);
use Data::Dumper;

my $upnp_server = $ARGV[0];
my $uuid = $ARGV[1] || Data::UUID->new->create_str();
$uuid =~ tr/A-F/a-f/;

my $socket = new IO::Socket::Multicast(
		LocalPort => '1900',
) or die "err $!";

$socket->mcast_add('239.255.255.250');

sub response {
	my $date = strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime);
	return <<EOR ;
HTTP/1.1 200 OK\r
DATE: $date\r
ST: upnp:rootdevice\r
USN: uuid:${uuid}::upnp:rootdevice\r
EXT:\r
SERVER: nanodlna SSDP responder\r
LOCATION: $upnp_server/root.xml?uuid=$uuid\r
Content-Length: 0\r
\r
EOR
}

my $data;
while(1) {
	$socket->recv($data, 1024);
	print "responding to " . $socket->peerhost . ':' . $socket->peerport . "\n";
	
	my @lines = map {chomp;$_} split /\n/, $data;
	foreach my $line (@lines) {
		if($line =~ /^man: "ssdp:discover"/i) {
			$socket->send(response());
		}
	}
}

$socket->close();
