# perl-email-mime-lazy
Email::MIME::Lazy

A modified version of Email::MIME that tries hard to keep everything
in memory only once.

Much of the code is copied directly from Email::MIME::Creator.

# Example

	my $cid = "AAAAAAAAAAA";
	my @parts;
	my %ct= ( png => "image/png", jpg => "image/jpeg", "" => "" );
	foreach my $file (@ARGV) {
	        my($ext)= ($file =~ /\.([^.]+)$/);
	        my $ct= $ct{ $ext || "" } || "application/octed-stream";
	        my $part= Email::MIME::Lazy->create(
	                header => [
	                        "Content-Id" => "<$cid>",
	                ],
	                attributes => {
	                        content_type => $ct,
	                        encoding => 'base64',
	                        disposition => 'inline',
	                        filename => basename($file),
	                },
	                body_file => $file,
	        );
	        push @parts, $part;
	
	        $cid++;
	}

	my $body= Email::MIME::Lazy->create(
	        attributes => {
	                content_type =>  "text/plain",
	                charset => "iso-8859-1",
	                encoding => 'quoted-printable',
	        },
	        body => "test test test =",
	);
	my $multipart= Email::MIME::Lazy->create(
	        header => [
	                "Content-Id" => "<qrd>",
	                To => 'Christian Borup <test@test.dk>',
	        ],
	        attributes => {
	                content_type => "multipart/mixed",
	        },
	        parts => [ $body, @parts ],
	);
	
	# Build and output the MIME structure, with constant mem usage
	my $iter= $multipart->as_string_iter;
	while(defined(my $buf= $iter->())) {
	        print STDOUT $buf;
	}
	
