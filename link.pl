#!/bin/perl

use strict;
use warnings;

my $ANDROID_VER = "android-29";
my $BUILD_VER   = "29.0.3";

my $SDK_DIR      = "../Sdk";
my $TOOLS_DIR    = "$SDK_DIR/build-tools/$BUILD_VER";
my $PLATFORM_DIR = "$SDK_DIR/platforms/$ANDROID_VER";

my $LIB_RES_DIR   = "lib/res";
my $LIB_CLASS_DIR = "lib/classes";

sub gen_rjava {
	my $pkg = shift;
	my $r_txt = shift;

	my @out = (
		"// Auto-generated by an unofficial tool",
		"",
		"package $pkg;",
		"",
		"public final class R {"
	);

	my $class = "";

	foreach my $line (@$r_txt) {
		my @info = split(/ /, $line, 4);
		if ($info[1] ne $class) {
			push(@out, "\t}") if (length($class) > 0);

			$class = $info[1];
			push(@out, "\tpublic static final class $class {");
		}

		push(@out, "\t\tpublic static final ${info[0]} ${info[2]}=${info[3]};");
	}

	push(@out, ("\t}", "}", ""));
	return \@out;
}

sub get_package_from_manifest {
	my $path = shift;

	if (!-f $path) {
		print("Could not find manifest file $path");
		return undef;
	}

	open(my $fh, '<', $path);
	read($fh, my $manifest, -s $fh);
	close($fh);

	if ($manifest =~ /package=["']([^"']+)/g) {
		return $1;
	}
	else {
		print("Could not find a suitable package name inside AndroidManifest.xml\n");
	}

	return undef;
}

sub gen_proj_rtxt {
	my @r_txt = ();
	my $type_idx = 0;
	foreach my $dir (<res/*>) {
		my $sub_idx = 0;
		if ($dir =~ /values/) {
			foreach my $f (<$dir/*.xml>) {
				open(my $fh, '<', $f);
				foreach (<$fh>) {
					if ($_ =~ /<(\w+).+name="([^"]+)"/) {
						my $id = sprintf('0x7f%02x%04x', $type_idx, $sub_idx);
						push(@r_txt, "int $1 $2 $id");
					}
					$sub_idx++;
				}
				close($fh);
			}
		}
		else {
			# 4 == length("res/")
			my $type = substr($dir, 4);
			my $len = length($dir) + 1;

			foreach my $f (<$dir/*>) {
				my $dot_idx = index($f, ".", $len);
				my $name = ($dot_idx < 0) ? substr($f, $len) : substr($f, $len, $dot_idx - $len);

				my $id = sprintf('0x7f%02x%04x', $type_idx, $sub_idx);
				push(@r_txt, "int $type $name $id");
				$sub_idx++;
			}
		}

		$type_idx++;
	}

	open(my $fh, '>', "build/R.txt");
	print $fh join("\n", @r_txt);
	close($fh);
}

sub update_res_ids {
	my $ids = shift;
	my $r_list = shift;

	my @table = (); # list of offsets to the provided files inside 'blob'
	my $fmt = "";   # format string to pack the list of files into a single blob
	my @files = ();

	my $size = 0;
	foreach (@$r_list) {
		open(my $fh, '<:raw', $_);
		my $s = -s $fh;
		read($fh, my $r, $s);
		close($fh);

		push(@table, $size);
		$fmt .= "a$s ";
		push(@files, $r);
		$size += $s;
	}
	push(@table, $size);

	my $blob = pack($fmt, @files);

	my @repl_list = ();

	foreach (@$ids) {
		my $new_id = substr($_, -10);

		my $nm_start = index($_, ':') + 1;
		my $nm_end = index($_, ' ') + 1;

		# name will look like "type variable "
		my $name = substr($_, $nm_start, $nm_end - $nm_start);
		$name =~ s/\// /;

		#print("\n$name: $new_id\n");

		# for each instance where 'name' gets defined as a single ID:
		my $name_reg = qr/$name(0x[0-9a-fA-F]+)/;
		while ($blob =~ /$name_reg/g) {
			my $match_len = length($1);
			my $off = (pos $blob) - $match_len;
			next if ($off < 0);

			# if the ID is not a complete ID (likely 0x0), just mark a single replacement
			if ($match_len != 10) {
				push(@repl_list, {"off" => $off, "len" => $match_len, "new" => $new_id});
				next;
			}

			# find the current file
			my $file_idx = 0;
			$file_idx++ while ($table[$file_idx] < $off);
			$file_idx--;

			#print("\tfound def in ${\$r_list->[$file_idx]}\n");

			my $id_reg = qr/$1/;
			while ($files[$file_idx] =~ /$id_reg/g) {
				my $pos = (pos $files[$file_idx]) - $match_len;
				next if ($pos < 0);

				push(@repl_list, {"off" => $pos + $table[$file_idx], "len" => 10, "new" => $new_id});
			}
		}
	}

	# since @ids (from ids.txt by aapt2 link) is not sorted in a convenient order, we sort the replacement list here
	#  so that for each offset, the necessary displacement can be calculated linearly
	my @replacements = sort { $a->{"off"} <=> $b->{"off"} } @repl_list;

	my $n_repl = @replacements;
	my $file_idx = 0;
	my $disp = 0;

	# this assumes that at least one replacement is needed in each file
	for (my $i = 0; $i < $n_repl; $i++) {
		my $repl = $replacements[$i];
		my $off = $repl->{"off"};
		my $len = $repl->{"len"};

		while ($off > $table[$file_idx + 1]) {
			$file_idx++;
			$table[$file_idx] += $disp;
		}

		substr($blob, $off + $disp, $len) = $repl->{"new"};
		$disp += 10 - $len; # disp += length($repl->{"new"}) - $len
	}
	$table[-1] += $disp;

	my $idx = 0;
	foreach (@$r_list) {
		open(my $fh, '>', $_);
		my $len = $table[$idx+1] - $table[$idx];
		print $fh substr($blob, $table[$idx], $len);
		close($fh);
		$idx++;
	}
}

sub compile_libs {
	foreach (<lib/*.aar>) {
		my $name = substr($_, 4, -4);

		my $in_path = "$LIB_RES_DIR/${name}_R.txt";

		if (!-f $in_path) {
			print("No resources file for $name, skipping...\n");
			next;
		}

		open(my $fh, '<', $in_path);
		chomp(my @r_txt = <$fh>);
		close($fh);

		# skip this library if the resources index is empty
		next if (@r_txt <= 1);

		my $package = get_package_from_manifest("$LIB_RES_DIR/${name}_mf.xml");
		next if (!defined($package)); # a bit harsh ;)

		my $out_ref = gen_rjava($package, \@r_txt);

		$package =~ s/\./\//g;
		my $out_path = "$LIB_CLASS_DIR/$package";
		mkdir $out_path if (!-d $out_path);

		$out_path .= "/R.java";
		open($fh, '>', $out_path);
		print $fh join("\n", @$out_ref);
		close($fh);

		system("javac -source 8 -target 8 -bootclasspath $PLATFORM_DIR/android.jar '$out_path'");
		unlink($out_path);
	}
}

if (-d "lib" && not (-d $LIB_RES_DIR && -d $LIB_CLASS_DIR)) {
	print(
		"This stage depends on library resources already being compiled.\n",
		"Run export-libs.pl first.\n"
	);
	exit;
}

print("Compiling library resources...\n");

mkdir("build") if (!-d "build");
system("$TOOLS_DIR/aapt2 compile -o build/res_libs.zip --dir lib/res/res");

print("Compiling project resources...\n");

# system("$TOOLS_DIR/aapt package -f -m -J "R" -M AndroidManifest.xml -S res -I $PLATFORM_DIR/android.jar");
system("$TOOLS_DIR/aapt2 compile -o build/res.zip --dir res");

print("Linking resources...\n");

system("$TOOLS_DIR/aapt2 link -o build/unaligned.apk --manifest AndroidManifest.xml -I $PLATFORM_DIR/android.jar --emit-ids ids.txt build/res.zip build/res_libs.zip");

if ($? != 0) {
	print("Resource linking failed\n");
	exit;
}

open(my $fh, '<', "ids.txt");
chomp(my @ids = <$fh>);
close($fh);

# for whatever reason, this doesn't work on my Cygwin setup
unlink("ids.txt");

print("Generating project R.txt...\n");

gen_proj_rtxt();

print("Updating resource IDs...\n");

my @r_list = ("build/R.txt");
push(@r_list, <$LIB_RES_DIR/*_R.txt>);

update_res_ids(\@ids, \@r_list);

if (-d $LIB_RES_DIR && -d $LIB_CLASS_DIR) {
	print("Generating library resource maps and compiling libraries...\n");
	compile_libs();

	print("Fusing library classes into a .JAR...\n");
	system("jar --create --file build/libs.jar -C '$LIB_CLASS_DIR' .");

	print("Compiling library .JAR into DEX bytecode...\n");
	system("java -Xmx1024M -Xss1m -cp $TOOLS_DIR/lib/d8.jar com.android.tools.r8.D8 --intermediate build/libs.jar --classpath $PLATFORM_DIR/android.jar --output build");
}

print("Generating project R.java...\n");

my $pkg = get_package_from_manifest("AndroidManifest.xml");
exit if (!defined($pkg));

open($fh, '<', "build/R.txt");
chomp(my @r_txt = <$fh>);
close($fh);

my $r_java = gen_rjava($pkg, \@r_txt);
open($fh, '>', "build/R.java");
print $fh join("\n", @$r_java);
close($fh);

print("Compiling project R.java...\n");

mkdir("build/R") if (!-d "build/R");
system("javac -source 8 -target 8 -bootclasspath $PLATFORM_DIR/android.jar build/R.java -d build/R");
system("jar --create --file build/R.jar -C build/R .");
