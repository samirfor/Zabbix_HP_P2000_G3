#!/usr/bin/perl

use warnings;
use strict;
use Net::SSL;
use LWP::UserAgent;
use Digest::MD5 qw(md5_hex);
use XML::Simple;
use JSON;

my $zabbixSender="/usr/bin/zabbix_sender";
my $zabbixConfd="/etc/zabbix/zabbix_agentd.conf";
my $sendFile="/var/tmp/zabbixSenderHPP2000";
my $zabbixSendCommand="$zabbixSender -c $zabbixConfd -i ";

my $USERNAME = "manage";
my $PASSWORD = "\!manage";

sub getHPP200Objects {
    my $ua = shift;
    my $sessionKey = shift;
    my $url = shift;
    my $objectName = shift;
    my $idName = shift;
    my $type = shift;
    my $zbxArray = shift;

    my $req = HTTP::Request->new(GET => $url);
    $req->header('sessionKey' => $sessionKey );
    $req->header('dataType' => 'api' );
    my $res = $ua->request($req);
    my $ref = XMLin($res->content, KeyAttr => "oid");
    foreach my $oid (values %{$ref->{OBJECT}}) {
        if ($oid->{name} eq $objectName) {
            my $reference;
            foreach my $entry (@{$oid->{PROPERTY}}) {
                if ($entry->{name} =~ /^($idName)$/) {
                    $reference = {'{#HP_P2000_ID}' => $entry->{content}, '{#HP_P2000_TYPE}' => $type};
                    last;
                }
            }
            push @{$zbxArray}, {%{$reference}};
        }
    }
}

sub getHPP200Stats {
    my $ua = shift;
    my $sessionKey = shift;
    my $url = shift;
    my $objectName = shift;
    my $idName = shift;
    my $colHash = shift;

    my $req = HTTP::Request->new(GET => $url);
    $req->header('sessionKey' => $sessionKey );
    $req->header('dataType' => 'api' );
    my $res = $ua->request($req);
    my $ref = XMLin($res->content, KeyAttr => "oid");
    foreach my $oid (values %{$ref->{OBJECT}}) {
        if ($oid->{name} eq $objectName) {
            my $reference;
            my $hashKey;
            foreach my $entry (@{$oid->{PROPERTY}}) {
                if ($entry->{name} =~ /^($idName|bytes-per-second-numeric|iops|number-of-reads|number-of-writes|data-read-numeric|data-written-numeric)$/) {
                    my $key = $1;
                    if ($key =~ /durable-id/) {
                        $hashKey = lc($entry->{content});
                    } elsif ($key eq $idName) {
                        $hashKey = $entry->{content};
                    } else {
                        $reference->{$key} = $entry->{content};
                    }
                }
            }
            $colHash->{$hashKey} = {%{$reference}};
        }
    }
}

sub getZabbixValues {
    my $hostname = shift;
    my $colHash = shift;
    my $type = shift;
    my $outputString = "";

    foreach my $key (keys %{$colHash}) {
        foreach my $itemKey (keys %{$colHash->{$key}}) {
            $outputString .= "$hostname hp.p2000.stats[$type,$key,$itemKey] $colHash->{$key}->{$itemKey}\n";
        }
    }

    $outputString;
}

sub logOut {
    my $ua = shift;
    my $sessionKey = shift;
    my $hostname = shift;

    my $url = "https://$hostname/api/exit";
    my $req = HTTP::Request->new(GET => $url);
    $req->header('sessionKey' => $sessionKey );
    $req->header('dataType' => 'api' );
    $ua->request($req);
}

my $hostname = $ARGV[0] or die("Usage: hp-msa-lld.pl <HOSTNAME> [lld|stats]");
my $function = $ARGV[1] || 'lld';

die("Usage: hp-msa-lld.pl <HOSTNAME> [lld|stats]") unless ($function =~ /^(lld|stats)$/);

my $md5_data = "${USERNAME}_${PASSWORD}";
my $md5_hash = md5_hex( $md5_data );

my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
my $url = "https://$hostname/api/login/" . $md5_hash;
my $req = HTTP::Request->new(GET => $url);
my $res = $ua->request($req);

my $ref = XMLin($res->content);
my $sessionKey;

if (exists $ref->{OBJECT}->{PROPERTY}->{"return-code"} && $ref->{OBJECT}->{PROPERTY}->{"return-code"}->{content} == 1) {
    $sessionKey = $ref->{OBJECT}->{PROPERTY}->{"response"}->{content};
} else {
    die($ref->{OBJECT}->{PROPERTY}->{"response"}->{content});
}

if ($function eq 'lld') {
    my $zbxArray = [];

    getHPP200Objects ( $ua, $sessionKey, "https://$hostname/api/show/controllers",
                       "controllers", "durable-id", "Controller", $zbxArray);

    getHPP200Objects ( $ua, $sessionKey, "https://$hostname/api/show/vdisks",
                       "virtual-disk", "name", "Vdisk", $zbxArray);

    getHPP200Objects ( $ua, $sessionKey, "https://$hostname/api/show/volumes",
                       "volume", "volume-name", "Volume", $zbxArray);

    print to_json({data => $zbxArray} , { ascii => 1, pretty => 1 }) . "\n";

    logOut($ua, $sessionKey, $hostname);
} else {
    my $ctrls = {};
    my $vdisks = {};
    my $volumes = {};
    my $outputString = "";

    getHPP200Stats ( $ua, $sessionKey, "https://$hostname/api/show/controller-statistics",
                 "controller-statistics", "durable-id", $ctrls);
    getHPP200Stats ( $ua, $sessionKey, "https://$hostname/api/show/vdisk-statistics",
                 "vdisk-statistics", "name", $vdisks);
    getHPP200Stats ( $ua, $sessionKey, "https://$hostname/api/show/volume-statistics",
                 "volume-statistics", "volume-name", $volumes);
    logOut($ua, $sessionKey, $hostname);

    $outputString .= getZabbixValues($hostname, $ctrls, "Controller");
    $outputString .= getZabbixValues($hostname, $vdisks, "Vdisk");
    $outputString .= getZabbixValues($hostname, $volumes, "Volume");

    $sendFile .= "_${hostname}_$$";
    die "Could not open file $sendFile!" unless (open(FH, ">", $sendFile));
    print FH $outputString;
    die "Could not close file $sendFile!" unless (close(FH));

    $zabbixSendCommand .= $sendFile;
    if ( qx($zabbixSendCommand) =~ /Failed 0/ ) {
        $res = 1;
    } else {
        $res = 0;
    }

    die "Can not remove file $sendFile!" unless(unlink ($sendFile));
    print "$res\n";
    exit ($res - 1);
}
