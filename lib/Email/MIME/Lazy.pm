package Email::MIME::Lazy;

use strict;
use warnings;

use Email::MIME::Header;
use Email::Simple::Creator;
use base qw(Email::MIME);

use MIME::Base64 qw(encode_base64);
use MIME::QuotedPrint qw(encode_qp);

my $CREATOR= "Email::Simple::Creator";
sub create {
	my($class, %args)= @_;

	my $self= bless +{}, $class;
	if($args{body_file}) {
		return unless -r $args{body_file};
		$self->{body_file}= $args{body_file};
	} elsif($args{body}) {
		$self->{body}= \$args{body};
	}

	# stolen from Email::MIME
	my $header = '';
	my %headers;
	if (exists $args{header}) {
		my @headers = @{ $args{header} };
		pop @headers if @headers % 2 == 1;
		while (my ($key, $value) = splice @headers, 0, 2) {
			$headers{$key} = 1;
			$CREATOR->_add_to_header(\$header, $key, $value);
		}
	}

	if (exists $args{header_str}) {
		my @headers = @{ $args{header_str} };
		pop @headers if @headers % 2 == 1;
		while (my ($key, $value) = splice @headers, 0, 2) {
			$headers{$key} = 1;

			$value = Encode::encode('MIME-Q', $value, 1);
			$CREATOR->_add_to_header(\$header, $key, $value);
		}
	}

	$CREATOR->_add_to_header(\$header, Date => $CREATOR->_date_header)
		unless exists $headers{Date};
	$CREATOR->_add_to_header(\$header, 'MIME-Version' => '1.0',);

	my %attrs = $args{attributes} ? %{ $args{attributes} } : ();

	# XXX: This is awful... but if we don't do this, then Email::MIME->new will
	# end up calling parse_content_type($self->content_type) which will mean
	# parse_content_type(undef) which, for some reason, returns the default.
	# It's really sort of mind-boggling.  Anyway, the default ends up being
	# q{text/plain; charset="us-ascii"} so that if content_type is in the
	# attributes, but not charset, then charset isn't changedand you up with
	# something that's q{image/jpeg; charset="us-ascii"} and you look like a
	# moron. -- rjbs, 2009-01-20
	if (
			grep { exists $attrs{$_} } qw(content_type charset name format boundary)
	   ) {
		$CREATOR->_add_to_header(\$header, 'Content-Type' => 'text/plain',);
	}

	$CREATOR->_finalize_header(\$header);
	$self->header_obj_set( Email::MIME::Header->new(\$header) );

	foreach (qw(content_type charset name format boundary encoding disposition filename)) {
		my $set = "$_\_set";
		$self->$set($attrs{$_}) if exists $attrs{$_};
	}

	if($args{parts}) {
		$self->content_type_set("multipart/mixed") unless $attrs{content_type};
		$self->{parts}= $args{parts};
	}

	$self
}

sub encoding_set {
	my ($self, $enc) = @_;
	$enc ||= '7bit';
	$self->header_set('Content-Transfer-Encoding' => $enc);
}

sub crlf { "\x0d\x0a" }

sub as_string {
	my $self= shift;
	my $buffer= "";
	my $iter= $self->as_string_iter;
	while(my $tmp= $iter->()) {
		$buffer .= $tmp;
	}
	$buffer
}

sub as_string_iter {
	my $self= shift;
	my $body_raw_iter;

	return sub {
		return $body_raw_iter->() if defined $body_raw_iter;
		$body_raw_iter= $self->body_raw_iter or die "";	
		return $self->header_obj->as_string . $self->crlf;
	};
}

sub body_raw_iter {
	my $self= shift;

	if($self->{body_file}) {
		return unless -r $self->{body_file};

		open my $file, "<", $self->{body_file} or return;
  		my $enc = $self->header('Content-Transfer-Encoding');
		if($enc =~ /base64/i) {
			return sub {
				read $file, my $buf, 60*57 or return undef;
				encode_base64($buf);
			};
		} elsif($enc =~ /quoted\-printable/i) {
			return sub {
				read $file, my $buf, -s $file or return undef;
				encode_qp($buf);
			};
		} else {
			return sub {
				read $file, my $buf, 1024  or return undef;
				$buf
			};
		}
	} elsif(my $ref= $self->{body}) {
  		my $enc = $self->header('Content-Transfer-Encoding');
		my $i= 0;
		if($enc =~ /base64/i) {
			my $len= length $$ref;
			return sub {
				return undef if 60*57*$i > $len;;
				encode_base64(substr($$ref, 60*57*$i++, 60*57))
			};
		} elsif($enc =~ /quoted\-printable/i) {
			return sub {
				return undef if $i++;
				encode_qp($$ref, $self->crlf)
			};
		} else {
			return sub {
				return undef if $i++;
				$$ref
			};
		}
	} elsif($self->{parts}) {
		my @part= @{$self->{parts}};

		unless($self->{ct}->{attributes}->{boundary}) {
			$self->{ct}->{attributes}->{boundary} ||=  Email::MessageID->new->user;
			$self->_compose_content_type( $self->{ct} );
		}
		my $seperator= $self->crlf . "--" . $self->{ct}->{attributes}->{boundary};

		my $iter;
		return sub {
			if(defined $iter) {
				# pass through data from the parts
				my $buf= $iter->();
				return $buf if defined $buf;

				# trigger a jump to the next part
				# dump seperator if there isn't one - next call will return undef
				$iter= undef;
				return $seperator. "--" . $self->crlf unless @part;
			} 

			if(@part) {
				my $part= shift @part;
				if($part->can("as_string_iter")) {
					$iter= $part->as_string_iter();
					return $seperator. $self->crlf;
				} else {
					$iter= sub { undef };
					return $seperator. $self->crlf . $part->as_string;
				}
			} else {
				return undef;
			}
		};
	}
}

1;
