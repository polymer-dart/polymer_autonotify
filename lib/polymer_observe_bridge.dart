library observe.polymer.bridge;

import "package:polymer/src/common/js_proxy.dart" show jsProxyReflectable;
import 'package:observe/src/metadata.dart';
export "package:observe/observe.dart";
import "package:reflectable/reflectable.dart";


Map<String, Iterable<Reflectable>> scopeMap = <String, Iterable<Reflectable>>{
  "observe": <Reflectable>[jsProxyReflectable]
};

@ScopeMetaReflector()
Iterable<Reflectable> reflectablesOfScope(String scope) => scopeMap[scope];


// Define observable const annotation as an alias to jsProxyReflectable
//const PolymerReflectable  observable = reflectable;


