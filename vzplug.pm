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
# Plugin Template and root class for vzdump
#
package vzplug;
use strict;
use warnings;

BEGIN {
    require Exporter;
    our @ISA = qw( Exporter );
    our %EXPORT_TAGS = ('all' => [ qw ( &new &id
                                        &prepare &snapshot &frozen &assemble
                                        )]);
    our @EXPORT_OK = ( @{$EXPORT_TAGS{'all'}});
    our @EXPORT = qw();
    our $VERSION = '0.1';
}

#
# Some handy back-references
#

sub mkpath {
    my $self = shift;
    return main::safe_mkpath @_;
}

sub rmtree {
    my $self = shift;
    return main::safe_rmtree @_;
}

sub debugmsg {
    my $self = shift;
    return main::debugmsg @_;
}

sub run_command {
    my $self = shift;
    return main::run_command @_;
}

sub new {
    my ($class,$name,$opts) = @_;
    my $self = {};
    while (my ($k, $v) = each (%$opts)){
	$self->{$k} = $v;
    }
    $self->{id} = $name;

    return bless($self, $class);
}

sub id {
    my ($self) = @_;
    $self->debugmsg('info',"Template plugin loaded successfully as $self->{id}!");
    return $self->{id};
}

#
# The required methods
#

sub debug {
    my ($self, $text) = @_;
    $self->debugmsg('info',$text) unless ( -z $text );
    while (my ($k, $v) = each (%$self)){
	$v = '(undef)' if(!defined($v));
	$self->debugmsg('info', $self->{id} ."->$k:\t$v");
    }
    
    return 1;
}

# Phase 1
sub prepare {
    my ($self, $logfd, $bckpar) = @_;
    return 1;
}

# Phase 2
sub snapshot {
    my ($self, $logfd, $bckpar) = @_;
    return 1;
}

# Phase 4
sub frozen {
    my ($self, $logfd, $bckpar) = @_;
    return 1;
}

# Phase 6
sub assemble {
    my ($self, $logfd, $bckpar) = @_;
    return 1;
}

# don't forget this!
1;
