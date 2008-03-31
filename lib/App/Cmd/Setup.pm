use strict;
use warnings;
package App::Cmd::Setup;

use App::Cmd ();
use App::Cmd::Command ();
use Carp ();
use Data::OptList ();

use Sub::Exporter -setup => {
  -as     => '_import',
  exports => [ qw(foo) ],
  collectors => [
    -app     => \'_make_app_class',
    -command => \'_make_command_class',
    -plugin  => \'_make_plugin_class',
  ],
};

sub import {
  goto &_import;
}

sub _app_base_class { 'App::Cmd' }

sub _make_app_class {
  my ($self, $val, $data) = @_;
  my $into = $data->{into};

  $val ||= {};
  Carp::confess "invalid argument to -app setup"
    if grep { $_ ne 'plugins' } keys %$val;

  Carp::confess "App::Cmd::Setup application setup requested on App::Cmd class"
    if $into->isa('App::Cmd');

  {
    no strict 'refs';
    push @{"$into\::ISA"}, $self->_app_base_class;
  }

  my @plugins;
  for my $plugin (@{ $val->{plugins} || [] }) {
    unless (eval { $plugin->isa($self->_plugin_base_class) }) {
      eval "require $plugin; 1" or die "couldn't load plugin $plugin: $@";
    }

    push @plugins, $plugin;
  }

  Sub::Install::install_sub({
    code => sub { @plugins },
    into => $into,
    as   => '_plugin_plugins',
  });

  return 1;
}

sub _command_base_class { 'App::Cmd::Command' }

sub _make_command_class {
  my ($self, $val, $data) = @_;
  my $into = $data->{into};

  Carp::confess "App::Cmd::Setup command setup requested on App::Cmd::Command class"
    if $into->isa('App::Cmd::Command');

  {
    no strict 'refs';
    push @{"$into\::ISA"}, $self->_command_base_class;
  }

  return 1;
}

{ package App::Cmd::Plugin; }
sub _plugin_base_class { 'App::Cmd::Plugin' }
sub _make_plugin_class {
  my ($self, $val, $data) = @_;
  my $into = $data->{into};

  Carp::confess "App::Cmd::Setup plugin setup requested on App::Cmd::Plugin class"
    if $into->isa('App::Cmd::Plugin');

  Carp::confess "plugin setup requires plugin configuration" unless $val;

  {
    no strict 'refs';
    push @{"$into\::ISA"}, $self->_plugin_base_class;
  }

  $val->{groups} = [ default => [ -all ] ] unless $val->{groups};

  my @exports;
  for my $pair (@{ Data::OptList::mkopt($val->{exports}) }) {
    Carp::confess "illegal value $pair->[1] in plugin configuration"
      if $pair->[1];

    push @exports, $pair->[0], \&_faux_curried_method;
  }

  $val->{exports} = \@exports;

  use Data::Dumper;
  Sub::Exporter::setup_exporter({
    %$val,
    into => $into,
    as   => 'import_from_plugin',
  });

  return 1;
}

sub _faux_curried_method {
  my ($class, $name, $arg) = @_;

  return sub {
    my $cmd = $App::Cmd::active_cmd;
    $class->$name($cmd, @_);
  }
}

1;
