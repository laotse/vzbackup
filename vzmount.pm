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

my $rsync = 'rsync';
my $lvcreate = 'lvcreate';
my $lvs = 'lvs';
my $lvremove = 'lvremove';
my $cstream = 'cstream';


BEGIN {
    require vzplug;
    our @ISA = qw( vzplug );
    our $VERSION = '0.1';
}

sub new {
    my ($class,$name,$opts,$vzdump_opts) = @_;
    my $self = vzplug->new($name,$opts,$vzdump_opts);

    $self->{mounts}   = [];
    $self->{tmpdirs}  = [];
    $self->{mpoint}   = "/mnt/vzmount";

    $self->{archive}  = ( !defined($vzdump_opts->{'noarch'}) ||
			  0 == $vzdump_opts->{'noarch'} )? 1 : 0;
    $self->{lvm}      = ( defined($vzdump_opts->{'lvm'}) &&
			  0 != $vzdump_opts->{'lvm'} )? 1 : 0;
    $self->{bwlimit}  = $vzdump_opts->{bwlimit};

    $self->{compress} = $vzdump_opts->{compress} unless( defined( $self->{compress} ));
    $self->{snapsize} = $vzdump_opts->{snapsize} unless( defined( $self->{snapsize} ));
    $self->{snapsize} = 1024 unless( defined( $self->{snapsize} ));

    die "Mount point for vzmount '$self->{mpoint}' is blocked.\n"
	if( -e $self->{mpoint} );


    return bless($self, $class);
}

sub id {
    my ($self) = @_;
    $self->debugmsg('info',"OpenVZ mount plugin loaded successfully as $self->{id}!");
    return $self->{id};
}

sub cleanup_all {
    my $self = shift;
    $self->lvm_cleanup(undef);
    $self->cleanup_tmpdirs;
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

sub make_tmpdir {
    my ($self, $dir, $logfd) = @_;

    while( -e $dir ){
	self->debugmsg('warn', "Temporary directory $dir already exists", $logfd);
	$dir = "$dir.$$";
    }
    $self->{tmpdirs} = [ @{$self->{tmpdirs}}, $self->mkpath( $dir ) ];

    return $dir;
}

sub cleanup_tmpdirs {
    my $self = shift;

    return if( ! defined( $self->{tmpdirs} ) );
    foreach my $d (@{$self->{tmpdirs}}){
	$self->rmtree( $d ) if( -d $d );
    }
    $self->{tmpdirs} = [];
}

sub rsync {
    my ($self,$from,$to,$text,$logfd) = @_;

    $from = "$from/" if( $from !~ /\/$/ );

    $self->debugmsg ('info', "starting $text sync $from to $to", $logfd);
    my $starttime = time();

    my $rsyncopts = "--stats -x --numeric-ids";
    $rsyncopts .= " --bwlimit=$self->{bwlimit}" if( defined( $self->{bwlimit} ));
    my $synccmd = "$rsync $rsyncopts -aH --delete --no-whole-file --inplace $from $to";

    $self->run_command ($logfd, $synccmd);

    my $delay = time () - $starttime;

    $self->debugmsg ('info', "$text sync finished ($delay seconds)", $logfd);
}

sub create_archive {
    my ($self, $src, $archive, $logfd) = @_;

    my $zflag = $self->{compress} ? 'z' : '';
    # set cstrem limit or none
    my $bwl = ( defined( $self->{bwlimit} ))? $self->{bwlimit}*1024 : undef;
    $bwl = ( defined( $bwl ))? "-t $bwl" : "";

    # backup all types except sockets
    my $findargs = "-xdev '(' -type s -prune ')' -o -print0";

    $self->debugmsg ('info', "creating temporary archive '$archive'", $logfd);
    my $cmd = "(cd $src; find . $findargs|tar c${zflag}pf - --totals --sparse --numeric-owner --no-recursion --ignore-failed-read --null -T -| $cstream $bwl >$archive)";
    $self->run_command ($logfd, $cmd);
}

sub mount_partition {
    my ($self, $dev, $fs, $multi, $logfd) = @_;

    $self->debugmsg ('info', "mounting $dev for syncing", $logfd);

    my @mopts = ( 'ro' );
    push @mopts, 'nouuid' if (($fs eq 'xfs') && $multi);
    my $most = "-o \"" . join(',',@mopts) . "\"";

    eval {
	$self->run_command ($logfd, "mount -t $fs $most $dev $self->{mpoint}");
    };
    return $@;
}

sub unmount {
    my ($self, $logfd) = @_;

    return "" if( ! -d $self->{mpoint});
    eval {
	$self->run_command ($logfd, "umount $self->{mpoint}");
    };
    return $@;
}

sub lvm_remove {
    my ($self, $mount, $logfd) = @_;

    return if( ! defined($mount->{lvmsnap}));

    $self->debugmsg ('info', "Removing LVM snapshot $mount->{snapdev}", $logfd) if $@;
    eval {
	$self->run_command ($logfd, "$lvremove -f $mount->{snapdev}");
    };
    $self->debugmsg ('error', $@, $logfd) if $@;

    delete $mount->{snapdev};
    delete $mount->{lvmsnap};
}

sub lvm_cleanup {
    my ($self, $logfd) = @_;

    eval { $self->run_command ($logfd, "umount $self->{mpoint}"); };

    $self->rmtree( $self->{mpoint} );

    foreach my $mount (@{$self->{mounts}}){
	next if( !defined($mount->{snapdev}) );

	$self->lvm_remove($mount, $logfd);
    }
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
	next if( 1 > scalar @fields );
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
	    $self->debugmsg('warn',"Strange mount entry: " . join(' ',@fields),$logfd);
	    next;
	}
	$mount->{dev} = $res[0];
	$mount->{fs}  = $res[1];
	$mount->{dir} = $res[6];

	my $path = File::Spec->canonpath($mount->{backup});
	$path = File::Spec->rel2abs($path);
	if( $path ne $mount->{dir} ){
	    $self->debugmsg('error',"mount directory $path ($mount->{backup}) is different from actual mount point $mount->{dir}",$logfd);
	    next;
	}

	$mount->{subdir} = $mount->{dev};
	$mount->{subdir} =~ s@^/?dev/@@;

	push @{$self->{mounts}}, $mount;
    }
    close MN;

    return 1 if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}});

    if( $self->{lvm} ) {
	my $mapping = main::get_lvm_mapping();

	foreach my $mount (@{$self->{mounts}}){
	    if (defined $mapping->{$mount->{dev}} ){
		($mount->{vg}, $mount->{lv}) =	@{$mapping->{$mount->{dev}}};
		$mount->{snapname} = "$mount->{lv}_vzm";
		$mount->{snapdev}  = "/dev/$mount->{vg}/$mount->{snapname}";
	    }
	}
    }

    $self->make_tmpdir( $self->{mpoint} );

    return 1;
}

sub snapshot {
    my ($self, $logfd, $bckpar) = @_;

    return 1 if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}});


    foreach my $mount (@{$self->{mounts}}){
	$mount->{snapdir} = "$bckpar->{snapdir}/$mount->{subdir}";
	if( $self->{archive} ){
	    $mount->{snapdir} = $self->make_tmpdir( $mount->{snapdir} );
	} else {
	    $self->mkpath( $mount->{snapdir} );
	}
	next if( defined($mount->{snapdev}) );

	$self->rsync($mount->{dir},$mount->{snapdir},"first",$logfd)
	    if($bckpar->{running});
    }

    return 1;
}

sub frozen {
    my ($self, $logfd, $bckpar) = @_;

    return 1 if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}});

    foreach my $mount (@{$self->{mounts}}){
	if( defined($mount->{snapdev}) ){
	    $self->debugmsg ('info', "creating lvm snapshot of $mount->{dev}", $logfd);
	    $self->run_command ($logfd, "$lvcreate --size $self->{snapsize}M --snapshot --name $mount->{snapname} /dev/$mount->{vg}/$mount->{lv}");
	    $mount->{lvmsnap} = 1;
	} else {
	    my $err = $self->mount_partition($mount->{dev},$mount->{fs},0,$logfd);
	    if($err){
		$self->debugmsg('error',"Cannot mount $mount->{dev}: $err -- abort!",$logfd);
		return 0;
	    }
	    $self->rsync($self->{mpoint},$mount->{snapdir},"final",$logfd);
	    $err = $self->unmount($logfd);
	    $self->debugmsg('warn',"Cannot unmount $mount->{dev}: $err",$logfd)
		if($err);
	}
    }

    return 1;
}

sub assemble {
    my ($self, $logfd, $bckpar) = @_;
    return 1 if( !defined($self->{mounts}) || 0 == scalar @{$self->{mounts}});

    foreach my $mount (@{$self->{mounts}}){
	next if( !$self->{archive} && !defined($mount->{snapname}));
	my $src = $mount->{snapdir};
	if( $mount->{snapdev} ){
	    my $err = $self->mount_partition($mount->{snapdev},$mount->{fs},1,$logfd);
	    if($err){
		$self->debugmsg('error',"Cannot mount $mount->{snapdev}: $err -- abort!",$logfd);
		return 0;
	    }
	    $src = $self->{mpoint};
	}
	if( $self->{archive} ){
	    my $arcname = $mount->{dev};
	    $arcname =~ s@^/?dev/@@;
	    $arcname =~ s@/@.@g;
	    my $arcpath = $bckpar->{tarfile};
	    $arcpath =~ s@/[^/]*$@@g;
	    $arcpath = '.' if( $arcpath eq "" );
	    $arcname = "$arcpath/$arcname";
	    my $arctmp = $arcname . ".tmp";
	    $arcname .= ($self->{compress})? ".tgz" : ".tar";

	    unlink $arctmp;
	    $self->create_archive($src,$arctmp,$logfd);
	    if( ! rename ($arctmp, $arcname)){
		$self->debugmsg('error',"unable to rename '$arctmp' to '$arcname'",$logfd);
		return 0;
	    }
	} else {
	    $self->rsync($self->{mpoint},$mount->{snapdir},"final",$logfd);
	}
	if( $mount->{snapdev} ){
	    my $err = $self->unmount($logfd);
	    $self->debugmsg('warn',"Cannot unmount $mount->{snapdev}: $err",$logfd) if($err);
	    $self->lvm_remove($mount,$logfd);
	}
    }

    return 1;
}

sub cleanup {
    my ($self, $logfd, $bckpar) = @_;

    $self->lvm_cleanup($logfd);
    $self->cleanup_tmpdirs;

    return 1;
}

# don't forget this
1;
