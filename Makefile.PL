use ExtUtils::MakeMaker;
WriteMakefile(
	NAME          => 'Finance::Bank::BNPParibas',
	VERSION_FROM  => 'lib/Finance/Bank/BNPParibas.pm',
	PREREQ_PM     => { 
		# 'Module::Foo' => $version,	
	},
	ABSTRACT_FROM => 'lib/Finance/Bank/BNPParibas.pm',
	AUTHOR        => 'Briac Pilpré <briac@cpan.org>',
);
