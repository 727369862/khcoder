package mysql_conc;
use strict;
use mysql_exec;

my ( $l_query, $l_hinshi, $l_katuyo, $l_length);

sub initialize{
	($l_query, $l_hinshi, $l_katuyo, $l_length) = ('','','','')
}

sub a_word{
	my $class = shift;
	my %args  = @_;
	my $self = \%args;
	bless $self, $class;

	unless ($args{length}){
		$args{length} = 20;
	}
	my (@left, @right);
	for (my $n = 1; $n <= $args{length}; ++$n){
		my $l = $args{length} - $n + 1;
		$l = 'l'."$l";
		push @left, $l;
		push @right, "r$n";
	}
	my @scanlist = (@left,"center",@right);
	$self->{scanlist} = \@scanlist;
	$self->{left}     = \@left;
	$self->{right}    = \@right;

	unless (
		   ( $l_query eq $args{query} )
		&& ( $l_hinshi eq $args{hinshi} )
		&& ( $l_katuyo eq $args{katuyo} )
		&& ( $l_length == $args{length} )
	){
		my $hyoso = $self->_hyoso;
		my $points = $self->_find($hyoso);
		$self->_get_data($points);
	}
	$l_query = $args{query};
	$l_hinshi = $args{hinshi};
	$l_katuyo = $args{katuyo};
	$l_length = $args{length};

	$self->_sort;
	return $self->_format;
}

sub _hyoso{
	my $self = shift;
	my %args = %{$self};
	
	# 表層語のリストアップ
	print "0: getting hyoso list\n";
	my $sql= '';
	$sql .= "SELECT hyoso.id\n";
	$sql .= "FROM genkei, hyoso, hselection";
	if ($args{katuyo}) {
		$sql .= ", katuyo";
	}
	$sql .= "\n";
	$sql .= "WHERE\n";
	$sql .= "	genkei.id = hyoso.genkei_id\n";
	$sql .= "	AND genkei.khhinshi_id = hselection.khhinshi_id\n";
	$sql .= "	AND hselection.ifuse = 1\n";
	if ($args{katuyo}){
		$sql .= "	AND hyoso.katuyo_id = katuyo.id\n";
		$sql .= "	AND katuyo.name = '$args{katuyo}'\n";
	}
	if ($args{hinshi}){
		$sql .= "	AND hselection.name = '$args{hinshi}'\n";
	}
	$sql .= "	AND genkei.name = '$args{query}'";
	my $d = mysql_exec->select($sql,1)->hundle->fetchall_arrayref;

	my @hyoso;
	foreach my $i (@{$d}){
		push @hyoso, $i->[0];
	}
	unless (@hyoso){
		return 0;
	}
	return \@hyoso;
}

sub _find{
	my $self = shift;
	my %args = %{$self};
	my @hyoso = @{$_[0]};
	my $sql = '';

	print "1: getting places\n";
	# 出現位置のリストアップ
	
	$sql = '';
	$sql .= "SELECT id\n";
	$sql .= "FROM hyosobun\n";
	$sql .= "WHERE\n";
	my $n = 0;
	foreach my $i (@hyoso){
		if ($n){
			$sql .= 'OR ';
		}
		$sql .= "hyoso_id = $i\n";
		++$n;
	}
	return mysql_exec->select($sql,1)->hundle->fetchall_arrayref;
}

sub _get_data{
	my $self = shift;
	my %args = %{$self};
	my $points = shift;
	my $sql = '';

	# Temp Table作成
	print "2: Creating temp table\n";
	mysql_exec->do("drop table temp_conc");
	$sql  = "create table temp_conc (\n";
	$sql .= "id int auto_increment primary key not null,\n";
	foreach my $i (@{$self->{scanlist}}){
		$sql .= "$i int,";
	}
	chop $sql;
	$sql .= ")";
	mysql_exec->do($sql,1);
	
	my $n = 0;
	my $temp = '';
	foreach my $i (@{$points}){
		my $p = $i->[0] - $args{length};
		my $n = $i->[0] + $args{length};
		my $sql  = "SELECT hyoso_id\n FROM hyosobun\n WHERE\n";
		$sql .= "id >= $p AND id <= $n \n";
		$sql .= "ORDER BY id";
		my $r = mysql_exec->select("$sql",1)->hundle->fetchall_arrayref;

		$temp .= "(";
		foreach my $h (@{$r}){
			$temp .= "$h->[0],";
		}
		chop $temp;
		$temp .= "),";

		if ($n == 300){
			chop $temp;
			my $sql  = "INSERT INTO temp_conc\n (";
			foreach my $h (@{$self->{scanlist}}){
				$sql .= "$h,";
			}
			chop $sql;		
			$sql .= ") VALUES $temp";
			mysql_exec->do("$sql",1);
			$temp = '';
		}
		++$n;
	}
	
	if ($temp){
		chop $temp;
		my $sql  = "INSERT INTO temp_conc\n (";
		foreach my $h (@{$self->{scanlist}}){
			$sql .= "$h,";
		}
		chop $sql;		
		$sql .= ") VALUES $temp";
		mysql_exec->do("$sql",1);
	}
}

sub _sort{                                        # ソート用テーブルの作成
	my $self = shift;
	my %args = %{$self};
	my $sql = '';

	print "3: Sorting...\n";
	my ($group, $n);
	foreach my $i ('sort1','sort2','sort3'){
		mysql_exec->do("drop table temp_conc_$i");
		if ($args{$i} eq "id"){ last; }
		mysql_exec->do("
			create table temp_conc_$i (
				id int auto_increment primary key not null,
				hyoso_id int not null,
				count int not null,
				temp0 int,
				temp1 int
			)
		",1);

		my $sql = '';
		$sql .= "INSERT INTO temp_conc_$i ( ";
		for (my $count = 0; $count < $n; ++$count){
			$sql .= "temp$count, ";
		}
		$sql .= "hyoso_id, count )\n";
		$sql .= "SELECT $group $args{$i}, count(*) as count\n";
		$sql .= "FROM temp_conc\n";
		$sql .= "GROUP BY $group $args{$i}\n";
		$sql .= "ORDER BY count DESC";
		mysql_exec->do($sql,1);
		$group .= "$args{$i},";
		++$n;
	}
	# 最終ソート・テーブル
	mysql_exec->do("drop table temp_conc_sort");
	mysql_exec->do("
		create table temp_conc_sort (
			id int auto_increment primary key not null,
			conc_id int not null
		)
	",1);

	$sql = '';
	$sql .= "INSERT INTO temp_conc_sort ( conc_id )\n";
	$sql .= "SELECT temp_conc.id\n";
	$sql .= "FROM   temp_conc,";
	foreach my $i ('sort1','sort2','sort3'){
		if ($args{$i} eq "id"){ last; }
		$sql .= "temp_conc_$i,";
	}
	chop $sql; $sql .= "\n";
	$n = 0; my @temp;
	foreach my $i ('sort1','sort2','sort3'){
		if ($args{$i} eq "id"){ last; }
		if ($n == 0){
			$sql .= "WHERE\n";
			$sql .= " temp_conc.$args{$i} = temp_conc_$i.hyoso_id\n";
		} else {
			$sql .= "AND temp_conc.$args{$i} = temp_conc_$i.hyoso_id\n";
			my $l = 0;
			foreach my $h (@temp){
				$sql .= "AND temp_conc.$h = temp_conc_$i.temp"."$l\n";
				++$l;
			}
		}
		push @temp, $args{$i};
		++$n;
	}
	$sql .= "ORDER BY ";
	foreach my $i ('sort1','sort2','sort3'){
		if ($args{$i} eq "id"){ last; }
		$sql .= "temp_conc_"."$i".".id,";
	}
	$sql .= "temp_conc.id";
	mysql_exec->do($sql,1);
}

sub _format{                                      # 結果の出力
	my $self = shift;
	print "4: Formating output...\n";
	
	my $result;
	foreach my $i (@{$self->{scanlist}}){
		my $sql = "SELECT hyoso.name FROM ( hyoso,temp_conc,temp_conc_sort )";
		$sql .= "WHERE";
		$sql .= "	temp_conc.$i = hyoso.id\n";
		$sql .= "	AND temp_conc.id = temp_conc_sort.conc_id\n";
		$sql .= "ORDER BY temp_conc_sort.id";
		$result->{$i} = mysql_exec->select($sql,1)->hundle->fetchall_arrayref;
	}

	#open (TOUT,">test2.txt") or die;
	#use Data::Dumper;
	#print TOUT Dumper($result);

	my $return;
	my $last = mysql_exec->select("SELECT COUNT(*) FROM temp_conc",1)->hundle->fetch->[0];
	--$last;

	for (my $n = 0; $n <= $last; ++$n){
		foreach my $i (@{$self->{left}}){
			$return->[$n][0] .= $result->{$i}[$n][0];
		}
		foreach my $i (@{$self->{right}}){
			$return->[$n][2] .= $result->{$i}[$n][0];
		}
		$return->[$n][1] = $result->{center}[$n][0];
	}

	return $return;
}

1;
