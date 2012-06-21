package NTPPool::Control::Zone;
use strict;
use base qw(NTPPool::Control);
use NP::Model;
use Combust::Constant qw(OK);
use JSON qw(encode_json);

sub zone_name {
  my $self = shift;
  my ($zone_name) = ($self->request->uri =~ m!^/zone/(?:graph|json/)?([^/]+?)(/|(-v6)?\.png)?$!);
  $zone_name ||= '.';
  $zone_name;
}

sub is_graph {
    my $self = shift;
    return unless $self->request->path =~ m!^/zone/graph!;
    return $self->request->path =~ m/-v6.png$/ ? 'v6' : 'v4';
}

# TODO: make the web interface actually do this
sub sort_order {
    my $self = shift;
    my $sort = $self->req_param('sort') || ''; 
    $sort = 'description' unless $sort eq 'server_count';
}

sub show_servers_access {
    my $self = shift;
    return $self->{_show_servers_access} if defined $self->{_show_servers_access};
    return $self->{_show_servers_access} = 1
      if $self->user 
        and $self->user->privileges
        and $self->user->privileges->see_all_servers;

    return $self->{_show_servers_access} = 0;
}

sub show_servers {
    my $self = shift;
    return 1 if $self->req_param('show_servers') and $self->show_servers_access;
    return 0;
} 

sub render {
  my $self = shift;
  my $zone_name = $self->zone_name;
  my $zone = NP::Model->zone->fetch(name => $zone_name);
  return 404 unless $zone;

  # discourage trailing slashes
  if (my ($path) = ( $self->request->path =~ m!^(.*)/$! )) {
      return $self->redirect( $1, 301 );
  }

  if (my $ip_version = $self->is_graph) {
      my $path = $zone->graph_path($ip_version);
      open my $fh, $path
        or warn "Could not open $path: $!" and return 403;
      
      my $mtime = (stat($fh))[9];
      $self->request->update_mtime($mtime);
      
      $self->cache_control('max-age=10800, s-maxage=7200');
      return OK, $fh, 'image/png';
  }
  elsif ($self->request->path =~ m!^/zone/json!) {
      my $data = NP::Model->zone_server_count->get_objects(
          query   => [zone_id => $zone->id],
          sort_by => 'date',
          limit   => 3000,
      );

    my @data = map {
        +{  d  => $_->date->date,
            ac => $_->count_active,
            rc => $_->count_registered,
            w  => $_->netspeed_active,
            iv => $_->ip_version,
          }
    } @$data;

      return OK, encode_json(\@data), 'application/json';
  }

  $self->tpl_param('zone' => $zone);

  $self->tpl_param('is_logged_in' => $self->show_servers_access );
  $self->tpl_param('show_servers' => $self->show_servers);
  if ($self->show_servers) {
      my @servers = sort { $a->ip cmp $b->ip } $zone->servers;
      $self->tpl_param('servers', \@servers);
  }

  unless ($self->show_servers_access) {
      $self->cache_control('s-maxage=900, maxage=1800');
  }
  else {
      $self->cache_control('private');
  }

  return OK, $self->evaluate_template('tpl/zone.html');
}

1;
