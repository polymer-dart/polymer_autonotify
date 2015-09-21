import 'dart:async';
import 'package:barback/barback.dart';
import "package:barback/src/transformer/transform.dart";
import 'package:smoke/codegen/recorder.dart';
import 'package:smoke/codegen/generator.dart';
import 'package:code_transformers/resolver.dart';
import 'package:code_transformers/src/dart_sdk.dart';
import "package:analyzer/analyzer.dart";
import 'package:analyzer/src/generated/element.dart';
import "package:observe/observe.dart";

class AutoNotifierTransformer extends Transformer with ResolverTransformer {
  final BarbackSettings _settings;
  Transform _transform;
  AssetId _primaryInputId;
  String _fileSuffix = '_autonotifier_bootstrap';
  Resolvers resolvers;

  AutoNotifierTransformer.asPlugin(this._settings) {
    resolvers = new Resolvers(dartSdkDirectory);
  }



/*
  classifyPrimary(AssetId id) {
    if (id.path.endsWith(".dart")) {
      return "dart";
    } else {
      return null;
    }
  }
*/


  Future<bool> isPrimary(assetOrId) {
    if (_settings.mode==BarbackMode.DEBUG) {
      return new Future.value(false);
    } else {
      return super.isPrimary(assetOrId);
    }
  }



  @override
  Future applyResolver(Transform transform, Resolver resolver) {
    _transform = transform;
    _primaryInputId = _transform.primaryInput.id;
    return _buildSmokeBootstrap(resolver);
  }

  /// Builds a Smoke bootstrapper that intializes static Smoke access
  /// and then calls the actual entry point.
  Future _buildSmokeBootstrap(Resolver resolver) async {
    // Initialize the Smoke generator and recorder
    var generator = new SmokeCodeGenerator();
    Recorder recorder = new Recorder(generator,
        (lib) => resolver.getImportUri(lib, from: _primaryInputId).toString());


    // Record each class in the library for our generator
    resolver.libraries.forEach((LibraryElement lib) {
      List<ClassElement> classes = lib.units.expand((u) => u.types);
      classes.where((ClassElement clazz) =>
      (clazz.allSupertypes.any((InterfaceType it) => it.name=="Observable" || it.name=="ChangeNotifier") ) && (
                    clazz.mixins.any((InterfaceType it) => it.name=="PolymerAutoNotifySupportMixin") ||
                    clazz.fields.any((FieldElement fe) => fe.metadata.any((ElementAnnotation ea) => ea.element.name=="observable")) ||
                    clazz.accessors.any((PropertyAccessorElement pa) => pa.metadata.any((ElementAnnotation ea) => ea.element.name=="observable"))))
        .forEach((ClassElement clazz) {
          //print("${_primaryInputId}: Recording ${clazz.name} from ${lib.name}");

          recorder.runQuery(clazz, new QueryOptions(includeProperties: true,includeFields:true,includeInherited:false,matches:(String name)=>!name.startsWith("_")));

      });
    });



    // Generate the Smoke bootstrapper
    StringBuffer sb = new StringBuffer();
    sb.write('library polymer_autonotifier.smoke_bootstrap;\n\n');
    generator.writeImports(sb);
    sb.write('\n');
    generator.writeTopLevelDeclarations(sb);
    sb.write('\ninitSmokeWithStaticConfiguration() => useGeneratedCode(\n');
    generator.writeStaticConfiguration(sb);
    // Call the entry point's main method
    sb.write(');\n');

    //print ("Conf generated:${sb}\n");

    // Add the Smoke bootstrapper to the output files
    var bootstrapId = _primaryInputId.changeExtension('${_fileSuffix}.dart');
    _transform.addOutput(new Asset.fromString(bootstrapId, sb.toString()));

    Asset origPrimaryAsset = await _transform.getInput(_primaryInputId);
    String origAssetContent = await origPrimaryAsset.readAsString();
    String p = bootstrapId.path;
    int pi=p.lastIndexOf("/");
    if (pi>=0) {
      p = p.substring(pi+1);
    }
    String result = origAssetContent.replaceAll(new RegExp("import\\s*['\"]package:smoke/mirrors.dart['\"]\s*;"),"import '${p}' as _notif;")
      .replaceAll(new RegExp("useMirrors\\(\\);"),"_notif.initSmokeWithStaticConfiguration();");
    //print("MODIFIED ASSET:${result}");
    _transform.addOutput(new Asset.fromString(_primaryInputId,result));
  }

  String get allowedExtensions => '.dart';
/*
  apply(AggregateTransform transforms) async {

    do {
      Transform transform = await newTransform(transforms);
      Resolver resolver = await resolvers.get(transform);
      try {
        await applyResolver(transform,resolver);
      } finally {
        resolver.release();
      }
    } while(true);
  }

*/
}