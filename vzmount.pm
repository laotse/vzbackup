#    Joint Copyright (C) 2007-2009
#         Proxmox Server Solutions GmbH
#         Dr. Lars Hanke (µAC - Microsystem Accessory Consult)
#
#    Copyright: vzdump, is under GNU GPL, the GNU General Public License.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; version 2 dated June, 1991.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the
#    Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
#    MA 02110-1301, USA.
#
#    Author: Lars Hanke <lars@lhanke.de>
#
#

#
# Plugin for backing up mounts of OpenVZ containers
#
package vzmount;
use strict;
use warnings;

use File::Basename;


BEGIN {
    require vzplug;
    our @ISA = qw( vzplug );
    our $VERSION = '0.1';
}

sub new {
    my ($class,$name,$opts,$vzdump_opts) = @_;
    my $self = vzplug->new($name,$opts,$vzdump_opts);

    $self->{mounts} = ();
    $self->{archive} = ( !defined($vzdump_opts->{'noarch'}) ||
			 0 == $vzdump_opts->{'noarch'} )? 1 : 0;
    $self->{lvm}     = ( defined($vzdump_opts->{'lvm'}) &&
			 0 != $vzdump_opts->{'lvm'} )? 1 : 0;

    return bless($self, $class);
}

sub id {
    my ($self) = @_;
    $self->debugmsg('info',"OpenVZ mount plugin loaded successfully as $self->{id}!");
    return $self->{id};
}

#
# helpers
#

sub unquote {
    my ($self,$text) = @_;

    return $text if($text =~ s/^\s*\"((?:\\\\|\\\"|[^\\\"])*)\"\s*$/$1/);
    return $text if($text =~ s/^\s*\'((?:\\\\|\\\'|[^\\\'])*)\'\s*$/$1/);
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;
    return $text;
}

#
# Debugging
#

sub list_mounts {
    my $self = shift;

    if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}}){
	print "No mounts in list!\n";
	return;
    }

    foreach my $m (@{$self->{mounts}}){
	print "*** Mount entry:\n";
	while (my ($k, $v) = each (%$m)){
	    print "$k\t=> $v\n";
	}
    }
}

#
# Methods, which we implement
#

# Phase 1
sub prepare {
    my ($self, $logfd, $bckpar) = @_;

    $self->{mounts} = ();
    return 1 if ($bckpar->{vmtype} ne 'openvz');

    my $cfgdir = dirname ($bckpar->{srcconf});
    my $mn = "$cfgdir/$bckpar->{vpsid}.mount";
    my $un = "$cfgdir/$bckpar->{vpsid}.unmount";
    return 1 if( ! -f "$mn" || ! -f "$un" );

    my $argpat = qr/(?:(?:\"(?:\\\"|[^\"])+\")|(?:\'(?:\\\'|[^\'])+\')|[^\s]+)/;

    if( ! open(MN,"<$mn") ){
	$self->debugmsg('error',"Cannot open mount file $mn");
	return 0;
    }

    while(<MN>){
	my @fields = $_ =~ /$argpat/g;
	my $cmd = $self->unquote( shift @fields );
	$cmd =~ s@^.*/@@g;
	next if ( $cmd ne "mount" );
	next if( grep { $_ eq "--bind" } @fields );
	my $mount = {};
	$mount->{backup} = pop @fields;
	my $fd = IO::File->new ("df -P -T '$mount->{backup}' 2>/dev/null|");
	<$fd>; #skip first line
	my @res = split(/\s+/,<$fd>);
	close ($fd);
	if( 7 != scalar @res){
	    $self->debugmsg('warn',"Strange mount entry: " . join(' ',@fields));
	    next;
	}
	$mount->{dev} = $res[0];
	$mount->{fs}  = $res[1];
	$mount->{dir} = $res[6];

	my $path = File::Spec->canonpath($mount->{backup});
	$path = File::Spec->rel2abs($path);
	if( $path ne $mount->{dir} ){
	    $self->debugmsg('error',"mount directory $path ($mount->{backup}) is different from actual mount point $mount->{dir}");
	    next;
	}
	push @{$self->{mounts}}, $mount;
    }
    close MN;

    return 1 if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}});

    my $mapping = main::get_lvm_mapping();

    foreach my $mount (@{$self->{mounts}}){
	($mount->{vg}, $mount->{lv}) =
	    @{$mapping->{$mount->{dev}}} if defined $mapping->{$mount->{dev}};
    }


    return 1;
}


# don't forget this
1;
