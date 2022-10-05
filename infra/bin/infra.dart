import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;

const String repo = 'oss://venom-testing';

/// The key is the package name, the value is the package's path.
Map<String, String> packages = {};

/// The number of packages key needs to build.
Map<String, int> pCount = {};

/// The packages that depend on the key.
Map<String, List<String>> revdeps = {};

/// An action associated with a package
Map<String, List<String>> actions = {};

// /// A [Queue] that stores actions that will be executed in the correct order.
// Queue<List<String>> aq = Queue();

/// Read stone.yml at [stonePath] and return the package name this stone file
/// represents.
Future<String> getPackageName(String stonePath) async {
  return loadYaml(await File(stonePath).readAsString())['name'];
}

Future<void> run(List<String> cmd,
    {bool sudo = false, String? workDir, bool dryRun = false}) async {
  final Process p;

  if (dryRun) {
    if (sudo) {
      print(['($workDir)', 'sudo'] + cmd);
    } else {
      print(['($workDir)'] + cmd);
    }
  } else {
    if (sudo) {
      p = await Process.start(
        'sudo',
        cmd,
        workingDirectory: workDir,
        mode: ProcessStartMode.inheritStdio,
      );
    } else {
      p = await Process.start(
        cmd[0],
        cmd.length > 1 ? cmd.sublist(1) : [],
        workingDirectory: workDir,
        mode: ProcessStartMode.inheritStdio,
      );
    }

    if ((await p.exitCode) != 0) {
      throw Exception("Process $cmd failed!");
    }
  }
}

Future<void> build(String package, {bool dryRun = false}) async {
  await run(
    ["boulder", "build", "-p", "venom-x86_64"],
    sudo: true,
    workDir: packages[package]!,
    dryRun: dryRun,
  );
}

Future<void> upload(String package, {bool dryRun = false}) async {
  if (dryRun) {
    print("Upload $package .stone packages...");
  } else {
    await for (final entity in Directory(packages[package]!)
        .list(recursive: false, followLinks: false)) {
      if (entity is File && p.extension(entity.path) == '.stone') {
        await run(
          [
            'aliyun',
            'oss',
            'cp',
            entity.path,
            p.join(repo, entity.path),
          ],
          dryRun: dryRun,
        );
      }
    }
  }
}

Future<void> delete(String package, {bool dryRun = false}) async {
  await run(
    [
      'aliyun',
      'oss',
      'rm',
      '-f',
      '-r',
      p.join(repo, packages[package]!),
    ],
    dryRun: dryRun,
  );
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser();
  parser.addOption(
    'packages',
    abbr: 'p',
    help: 'Path of the `pkgs.yml` file.',
    defaultsTo: 'pkgs.yml',
  );
  parser.addFlag(
    'verbose',
    abbr: 'v',
    defaultsTo: false,
  );
  parser.addFlag(
    'dry-run',
    abbr: 'n',
    defaultsTo: true,
  );

  final argResults = parser.parse(arguments);

  final String pkgsFile = argResults['packages'];
  final YamlDocument pkgsDoc =
      loadYamlDocument(await (File(pkgsFile).readAsString()));

  // Read pkgs.yml file
  if (pkgsDoc.contents.value is! YamlMap) {
    stderr.writeln(
        "Unable to parse $pkgsFile as YamlMap, has type ${pkgsDoc.contents.value.runtimeType}");
    exit(1);
  }

  // Build dependency graph
  final YamlMap pkgsMap = pkgsDoc.contents.value;
  for (var entry in pkgsMap.value.entries) {
    final String pkg = entry.key;
    final YamlList? value = entry.value;

    if (value != null) {
      for (final builddep in value) {
        revdeps.putIfAbsent(builddep, () => []).add(pkg);
      }
      pCount[pkg] = value.length;
    } else {
      pCount[pkg] = 0;
    }
  }

  // Scan everything to find where each package's corresponding location is at.
  await for (final bdir
      in Directory('.').list(recursive: false, followLinks: false)) {
    // Skip some directories that we clearly don't need to traverse...
    if (p.basename(bdir.path) == '.git') {
      continue;
    }

    if (bdir is Directory) {
      await for (final entity
          in bdir.list(recursive: true, followLinks: false)) {
        final String stoneYml = p.join(entity.path, 'stone.yml');

        if (await File(stoneYml).exists()) {
          final pkgName = await getPackageName(stoneYml);

          packages[pkgName] = entity.path.substring(2);
        }
      }
    }
  }

  // Check if there is a non-existent package
  for (final entry in pCount.entries) {
    if (!packages.containsKey(entry.key)) {
      stderr.writeln("Whoa, package ${entry.key} does not exist in the repo!");
      exit(1);
    }
  }

  final syncFile = File("main.sync");
  await for (final line in syncFile
      .openRead()
      .transform(utf8.decoder)
      .transform(LineSplitter())) {
    final List<String> tokens = line.trim().split(' ');
    if (tokens.isEmpty) {
      continue;
    } else if (tokens[0].isNotEmpty && tokens[0][0] == '#') {
      continue;
    } else {
      final String package;

      switch (tokens[0]) {
        case 'add':
          assert(tokens.length == 2);
          package = tokens[1];
          break;
        case 'rm':
          assert(tokens.length == 2);
          package = tokens[1];
          assert(package.contains('/'));
          await delete(package);
          break;
        case 'update':
          assert(tokens.length == 2);
          package = tokens[1];
          break;
        default:
          throw Exception('What the heck is ${tokens[0]} ?!');
      }

      actions[package] = tokens;
    }
  }

  bool dryRun = argResults['dry-run'];

  Queue<String> q = Queue();
  for (final entries in pCount.entries) {
    if (entries.value == 0) {
      q.add(entries.key);
    }
  }

  while (q.isNotEmpty) {
    final pkg = q.first;
    q.removeFirst();

    if (revdeps.containsKey(pkg)) {
      for (var revdep in revdeps[pkg]!) {
        pCount[revdep] = pCount[revdep]! - 1;

        if (pCount[revdep] == 0) {
          q.add(revdep);
        }
      }
    }

    // Execute the action
    if (actions.containsKey(pkg)) {
      final action = actions[pkg]!;

      print('''


/////////////////////////////////////////////////////////////////////
Building $pkg using $action
/////////////////////////////////////////////////////////////////////''');

      switch (action[0]) {
        case 'add':
          await build(pkg, dryRun: dryRun);
          await upload(pkg, dryRun: dryRun);
          break;
        case 'update':
          await build(pkg, dryRun: dryRun);
          await delete(pkg, dryRun: dryRun);
          await upload(pkg, dryRun: dryRun);
          break;
        default:
      }

      if (!dryRun) {
        print('Succeeded, wait 1 minute for indexing to finish...');
        await Future.delayed(Duration(minutes: 1));
      }
    }
  }
}

// enum ActionType { mv, add, rm, update }
// 
// class Action {
//   static const String repo = "oss://venom-testing";
// 
//   final ActionType _type;
//   /// The package that the action will modify.
//   ///
//   /// For [ActionType.mv], this will be the path to the old directory.
//   final String receiver;
//   /// The new path this package will be moved to. Only valid for
//   /// [ActionType.mv].
//   String? to;
// 
//   Action(this._type, this.receiver, [this.to]);
// 
//   ActionType get type => _type;
// 
//   Future<void> execute() async {
//     late final List<String> prepArgs;
//     late final List<String> ossArgs = [];
// 
//     switch (_type) {
//       case ActionType.mv:
//         prepArgs = [
//           "cp",
//           p.join(Action.repo, to!),
//           p.join(Action.repo, receiver),
//         ];
//         break;
//       case ActionType.add:
//         break;
//       case ActionType.rm:
//         break;
//       case ActionType.update:
//         break;
//       default:
//         throw Exception("I don't recognize this action type!");
//     }
// 
//     final oss = await Process.start(
//       "oss",
//       ossArgs,
//       mode: ProcessStartMode.inheritStdio,
//     );
//     final ossExitCode = await oss.exitCode;
//     if (ossExitCode != 0) {
//     }
//   }
// }


