#! /usr/bin/env perl

use Dancer2;
use XML::XPath;
use XML::Entities;
use HTML::Entities;
use File::MimeInfo;
use URI::Escape;
use Data::Dumper;

use strict;
use warnings;

my $root_dir = $ARGV[0];
my $http_server = $ARGV[1];

%HTML::Entities::char2entity = %{
	XML::Entities::Data::char2entity('all');
};

sub path_to_objid {
	my ($path) = @_;

	if($path eq $root_dir) {
		return '0';
	}

	my $root = "$root_dir/";

	if(substr($path, 0, length($root)) eq $root) {
		$path = substr($path, length($root));
		return unpack("H*", $path);
	} else {
		die "invalid path $path";
	}
}

sub objid_to_path {
	my ($obj_id) = @_;
	
	if($obj_id eq '0') {
		return $root_dir;
	} else {
		my $path = pack("H*", $obj_id);

		foreach my $elem (split(/\//, $path)) {
			if($elem eq '..') {
				die "trying .. in $obj_id";
			}
		}

		return "$root_dir/$path"; 
	}
}

sub stat_file {
	my ($fname) = @_;
	my $file_id = path_to_objid($fname);
	my $mime = mimetype($fname);
	my $server_path = uri_escape(substr($fname, length($root_dir) + 1));

	my $noext = $fname;
	$noext =~ s/\.([^.]+)$//;

	my $subres = '';

	if((-e "$noext.srt") && ($1 ne 'srt')) {
		my $server_srt = uri_escape(substr("$noext.srt", length($root_dir) + 1));
		$subres .= "<res protocolInfo=\"http-get:*:text/srt:*\">$http_server/$server_srt</res>";
	}

	# TODO
	return {
		class => 'object.item.videoItem',
		date => '2000-01-01T00:00:00',
		res => <<EOR
	<res protocolInfo="http-get:*:$mime:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000">$http_server/$server_path</res>
	$subres
EOR
	};
}

sub path_to_xml {
	my ($dir, $entry) = @_;

	my $path = "$dir/$entry";
	my $id = path_to_objid($path);
	my $parent = path_to_objid($dir);
	my $name = encode_entities($entry);

	if(-d $path) {
		return <<EOR ;
	<container id="$id" parentID="$parent" restricted="1">
		<dc:title>$name</dc:title>
		<upnp:class>object.container.storageFolder</upnp:class>
		<upnp:storageUsed>-1</upnp:storageUsed>
	</container>
EOR
	} elsif((-f $path) || (-l $path)) {
		my $i = stat_file($path);

		if($i) {
			return <<EOR ;
	<item id="$id" parentID="$parent" restricted="1">
		<dc:title>$name</dc:title>
		<upnp:class>$i->{class}</upnp:class>
		<dc:date>$i->{date}</dc:date>
		$i->{res}
	</item>
EOR
		} else {
			return '';
		}
	} else {
		return '';
	}
}

sub get_listing {
	my ($obj_id, $start, $count) = @_;

	my $items = '';

	my $path = objid_to_path($obj_id);
	print "listing for $path $start - $count\n";
	opendir(my $dh, $path) || die "opendir($path): $!";
	my @items = sort grep { !/^\.$/ && !/^\.\.$/ } readdir($dh);
	closedir $dh;
	
	my $total = scalar @items;
	my $numret = 0;

	for(my $i = $start; $numret <= $count && exists($items[$i]); $i++) {
		$items .= path_to_xml($path, $items[$i]);
		$numret++;
	}

	return (<<EOR , $numret, $total);
<?xml version="1.0"?>
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
$items
</DIDL-Lite>
EOR

}

post '/ctl/content_dir' => sub {
	my $data = request->content;
	my $xp = XML::XPath->new(xml => $data);

	$xp->set_namespace('s', 'http://schemas.xmlsoap.org/soap/envelope/');
	$xp->set_namespace('u', 'urn:schemas-upnp-org:service:ContentDirectory:1');

	my @browse_node = $xp->findnodes('/s:Envelope/s:Body/u:Browse');
	if(exists $browse_node[0]) {
		my $browse = $browse_node[0];

		my $obj_id = $browse->find('//ObjectID/text()');
		my $flag = $browse->find('//BrowseFlag/text()');
		my $start = $browse->find('//StartingIndex/text()');
		my $cnt = $browse->find('//RequestedCount/text()');

		# string interpolation is necessary it seems
		if("$flag" ne 'BrowseDirectChildren') {
			print "unknown flag $flag in: \n$data\n";
			die 'unkflag';
		}

		content_type 'text/xml; charset="utf-8"';

		my ($result, $numret, $total) = get_listing("$obj_id", "$start", "$cnt");
		my $updid = 1;

		$result = encode_entities($result);

		return <<EOR ;
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>$result</Result>
<NumberReturned>$numret</NumberReturned>
<TotalMatches>$total</TotalMatches>
<UpdateID>$updid</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
EOR
		
	} else {
		die "unkrequest:\n$data\n";
	}
};

get '/root.xml' => sub {
	my $uuid = params->{uuid};
	content_type 'text/xml';
	template 'root.tt', { uuid => $uuid };
};

any qr{.*} => sub {
	print "weird route" . Dumper(request->headers(), request->uri());
	'404';
};

start;
