@HtmlImport('polymer_autonotify.html')
library draft.polymer.autonotify;

import "package:polymer/polymer.dart";
import "package:web_components/web_components.dart" show HtmlImport;
import "package:observe/observe.dart";
import "package:logging/logging.dart";
import "dart:async";
import "dart:js";
import "package:reflectable/reflectable.dart";
export "package:polymer_autonotify/polymer_observe_bridge.dart";

Logger _logger = new Logger("draft.polymer.autonotify");

SplicesData __CURRENT_SPLICE_DATA;

final JsObject DartAutonotifyJS = () {
  JsObject j = context["Polymer"]["Dart"]["AutoNotify"];
  j["updateJsVersion"] = (js) {
    var dart = convertToDart(js);
    var js1 = js;
    js = convertToJs(dart);

    ChangeVersion jsChange = new ChangeVersion(js);
    ChangeVersion dartChange = new ChangeVersion(dart);
    //jsChange.version=dartChange.version+1;
    jsChange.comingFromJS = true;
    //_logger.fine("COMING FROM JS : ignore when darty");
  };

  j["collectNotified"] = (el, path) {
    // Mark this element as notified
    if (__CURRENT_SPLICE_DATA != null) {
      var x = convertToDart(el);
      __CURRENT_SPLICE_DATA.setDone(x, path);
      return true;
    }
    return false;
    //_logger.fine("This is already notified : ${x}");
  };

  j["createAutonotifier"] = (el) {
    //_logger.fine("Create autonotifier for ${el}");
    el = convertToDart(el);
    //_logger.fine("Darty : ${el}");
    new PropertyNotifier.from(el);
    //_logger.fine("Done");
  };

  j["destroyAutonotifier"] = (el) {
    //_logger.fine("Create autonotifier for ${el}");
    el = convertToDart(el);
    //_logger.fine("Darty : ${el}");
    new PropertyNotifier.from(el).destroy();
    PropertyNotifier.evict(el);
    //_logger.fine("Done");
  };

  return j;
}();

abstract class PropertyNotifier {
  static final Expando<PropertyNotifier> _notifiersCache = new Expando();
  static final Map _cycleDetection = {};

  bool notifyPath(String name, var newValue);
  notifySplice(String path, SplicesData spliceData);

  PropertyNotifier() {}

  factory PropertyNotifier.from(target) {
    if (_cycleDetection[target] != null) {
      _logger.warning("A cycle in notifiers as been detected : ${target}");
      return null;
    }
    // Expandos don't work for these objects.
    if (target is String || target is num || target == null || target is bool) {
      return null;
    }
    _cycleDetection[target] = true;
    PropertyNotifier n;
    try {
      n = _notifiersCache[target];
      if (n == null) {
        n = () {
          if (target is PolymerMixin) {
            return new PolymerElementPropertyNotifier(target);
          } else if (target is List || target is ObservableList) {
            return new ListPropertyNotifier(target);
          } else if (target is Observable) {
            return new ObservablePropertyNotifier(target);
          } else {
            return null;
          }
        }();
      }

      if (n != null) {
        _notifiersCache[target] = n;
      }
    } finally {
      _cycleDetection.remove(target);
    }
    return n;
  }

  void destroy();

  static PropertyNotifier evict(target) => _notifiersCache[target] = null;
}

abstract class HasChildrenMixin implements PropertyNotifier {
  Map<String, HasParentMixin> subNodes = {};

  void addChildren(target) {
    Map<String, dynamic> children = discoverChildren(target);
    children.forEach((String name, subTarget) {
      HasParentMixin prev = subNodes.remove(name);
      if (prev != null) {
        prev.removeReference(name, this);
      }

      HasParentMixin child = new PropertyNotifier.from(subTarget);
      if (child != null) {
        subNodes[name] = child..addReference(name, this);
      }
    });
  }

  Map<String, dynamic> discoverChildren(target);

  void destroyChildren() {
    subNodes.forEach((String name, HasParentMixin child) {
      child.removeReference(name, this);
    });
    subNodes.clear();
  }
}

abstract class HasParentMixin implements PropertyNotifier {
  Map<String, List<HasChildrenMixin>> parents = {};

  void removeReference(String name, HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents[name];
    if (refs != null) {
      refs.remove(parent);
      if (refs.length == 0) {
        parents.remove(name);
      }
    }
    if (parents.isEmpty) {
      // no reason to exist if no one references me
      destroy();
    }
  }

  void addReference(String name, HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents.putIfAbsent(name, () => new List());
    refs.add(parent);
  }

  void renameReference(
      String fromName, String toName, HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents[fromName];
    if (refs != null) {
      refs.remove(parent);
      if (refs.length == 0) {
        parents.remove(fromName);
      }
    }
    refs = parents.putIfAbsent(toName, () => new List());
    refs.add(parent);
  }

  bool notifyPath(String name, newValue) {
    parents.forEach((String parentName, List<PropertyNotifier> parents1) {
      parents1.forEach((PropertyNotifier parent) {
        parent.notifyPath(parentName + "." + name, newValue);
      });
    });
  }

  notifySplice(String path, SplicesData spliceData) {
    parents.forEach((String parentName, List<PropertyNotifier> parents1) {
      parents1.forEach((PropertyNotifier parent) {
        parent.notifySplice(parentName + "." + path, spliceData);
      });
    });
  }
}

abstract class HasChildrenReflectiveMixin implements HasChildrenMixin {
  Map discoverChildren(target) {
    InstanceMirror im = jsProxyReflectable.reflect(target);
    Iterable<DeclarationMirror> fields = im.type.declarations.values
        .where((DeclarationMirror dm) =>
            ((dm is MethodMirror) && ((dm as MethodMirror).isGetter)) ||
                (dm is VariableMirror))
        .where((DeclarationMirror dm) =>
            dm.metadata.any((m) => m is ObservableProperty));
    return new Map.fromIterable(fields,
        key: (DeclarationMirror f) => f.simpleName,
        value: (DeclarationMirror f) => im.invokeGetter(f.simpleName));
  }

  StreamSubscription _sub;

  init(Observable _target) {
    addChildren(_target);
    _sub = observe(_target);
  }

  StreamSubscription observe(Observable target) {
    // Attach listener too
    return target.changes.listen((List<ChangeRecord> recs) {
      Map newValues = {};
      recs.where((ChangeRecord cr) => cr is PropertyChangeRecord).forEach(
          (PropertyChangeRecord pcr) => newValues[pcr.name] = pcr.newValue);

      newValues.forEach((String sym, val) {
        String name = sym;
        new ChangeVersion(target).version++;
        notifyPath(name, val);

        // Replace observer
        HasParentMixin child = subNodes.remove(name);
        if (child != null) {
          child.removeReference(name, this);
        }

        child = new PropertyNotifier.from(val);
        if (child != null) {
          subNodes[name] = child..addReference(name, this);
        }
      });
    });
  }

  void cleanUpListener() {
    _sub.cancel();
  }
}

class SpliceData {
  int index;
  int added;
  List removed;

  SpliceData(this.index, this.added, this.removed);

  void apply(List dartArray) {
    JsArray jsArray = convertToJs(dartArray) as JsArray;
    jsArray.callMethod(
        "splice",
        [index, removed.length]
          ..addAll(dartArray.sublist(index, index + added).map(convertToJs)));
  }
}

class SplicesData {
  //static int counter=0;
  //int id = counter++;
  List array;

  List<SpliceData> spliceData;

  void apply() {
    spliceData.forEach((SpliceData sd) => sd.apply(array));
  }

  Map _splices;

  Map get splices {
    if (_splices == null) {
      List indexSplices = spliceData
          .map((SpliceData sd) => {
                "index": sd.index,
                "addedCount": sd.added,
                "removed": sd.removed
              })
          .toList();
      _splices = {
        "object": array,
        "splices": PolymerCollection.applySplices(array, indexSplices),
        "indexSplices": indexSplices,
        "_applied": true
      };
    }

    return _splices;
  }

  SplicesData(this.array);

  Map<Object, Set> done = new Map<Object, Set>();

  bool checkDone(me, path) {
    if (done.containsKey(me) && done[me].contains(path)) {
      //_logger.fine("#${id} CHECK DONE ALREADY DONE ${me} -> ${path}");
      return false;
    } else {
      //_logger.fine("#${id} CHECK DONE FIRST TIME ${me} -> ${path}");
      setDone(me, path);
      return true;
    }
  }

  void setDone(me, path) {
    done.putIfAbsent(me, () => new Set()).add(path);
  }
}

class PolymerElementPropertyNotifier extends PropertyNotifier
    with HasChildrenMixin, HasChildrenReflectiveMixin, HasParentMixin {
  PolymerMixin _element;
  //Expando<ChangeVersion> _notifyVersionTrackingExpando = new Expando();

  PolymerElementPropertyNotifier(PolymerMixin element) {
    _element = element;
    if (!(element is Observable)) {
      throw "Using notifier on non observable Polymer";
    }
    init(_element);
  }

  bool notifyPath(String name, newValue) {
    //if (_logger.isLoggable(Level.FINE)) {
    //  _logger.fine("${_element} NOTIFY ${name} with ${newValue}");
    //}
    // Sync'em

    // Notify parents too
    parents.forEach((String parentName, List<PropertyNotifier> parents1) {
      parents1.forEach((PropertyNotifier parent) {
        parent.notifyPath(parentName + "." + name, newValue);
      });
    });

    return _element.notifyPath(name, newValue);
  }

  notifySplice(String path, SplicesData spliceData) {
    //_logger.fine("Notifiyng SPLICE ${spliceData.id} FOR ${_element.id}");

    parents.forEach((String parentName, List<PropertyNotifier> parents1) {
      parents1.forEach((PropertyNotifier parent) {
        parent.notifySplice(parentName + "." + path, spliceData);
      });
    });

    JsArray js = convertToJs(spliceData.array);
    ChangeVersion jsVersion = new ChangeVersion(js);
    ChangeVersion dartVersion = new ChangeVersion(spliceData.array);

    if (jsVersion.comingFromJS) {
      jsVersion.version = dartVersion.version;
      return;
    }

    // Sync'em
    if (jsVersion.version != dartVersion.version) {
      jsVersion.version = dartVersion.version;

      //_logger.fine("#${spliceData.id} CHANGING JS ");

      spliceData.apply();
    }

    if (spliceData.checkDone(_element, path)) {
      __CURRENT_SPLICE_DATA = spliceData;
      try {
        (_element as PolymerElement).set(path, spliceData.splices);
        //_element.jsElement.callMethod("set",["${path}.splices",spliceData.splices]);
        //_element.notifyPath(,spliceData.splices);
        /*
          JsArray removed = new JsArray.from(spliceData.removed.map(convertToJs));
          _element.jsElement.callMethod("_notifySplice", [js, path, spliceData.index, spliceData.added, removed]);
          */
      } finally {
        __CURRENT_SPLICE_DATA = null;
        // garbage collection you are my friend.
      }
    }
  }

  void destroy() {
    cleanUpListener();
    destroyChildren();
    PropertyNotifier.evict(_element);
  }
}

class ChangeVersion {
  static final Expando<ChangeVersion> _versionTrackingExpando = new Expando();
  int version;
  bool comingFromJS = false;

  ChangeVersion._([this.version = 0]);

  factory ChangeVersion(target, {Expando<ChangeVersion> fromExpando}) {
    if (fromExpando == null) {
      fromExpando = _versionTrackingExpando;
    }
    ChangeVersion v = fromExpando[target];
    if (v == null) {
      v = new ChangeVersion._();
      fromExpando[target] = v;
    }
    return v;
  }
}

class ObservablePropertyNotifier extends PropertyNotifier
    with HasParentMixin, HasChildrenMixin, HasChildrenReflectiveMixin {
  Observable _target;

  ObservablePropertyNotifier(Observable target) {
    _target = target;
    init(_target);
  }

  void destroy() {
    cleanUpListener();
    destroyChildren();
    PropertyNotifier.evict(_target);
  }
}

class ListPropertyNotifier extends PropertyNotifier
    with HasParentMixin, HasChildrenMixin {
  List _target;
  StreamSubscription _sub;

  ListPropertyNotifier(List target) {
    _target = target;
    addChildren(_target);

    if (_target is ObservableList) {
      // Observe changes on list too
      _sub = (target as ObservableList)
          .listChanges
          .listen((List<ListChangeRecord> rc) {
        //_logger.fine("PRocessing changes ${rc.length}");
        // Notify splice
        SplicesData splicesData = new SplicesData(_target);
        splicesData.spliceData = rc
            .
            //..sort((ListChangeRecord rc1,ListChangeRecord rc2) => rc1.removed!=null && rc1.removed.length>0 ? 1:-1)
            map((ListChangeRecord lc) {
          // Avoid loops when splicing jsArray
          new ChangeVersion(_target).version++;

          // Adjust references

          int adjust = lc.addedCount - lc.removed.length;

          // Fix observers
          if (lc.removed != null && lc.removed.length > 0) {
            for (int i = 0; i < lc.removed.length; i++) {
              String name = (lc.index + i).toString();
              subNodes.remove(name).removeReference(name, this);
            }

            // fix path on the rest (use subnodes length because it is the actual remainng
            if (adjust < 0) {
              for (int i = lc.index; i < subNodes.length; i++) {
                String fromName = (i - adjust).toString();
                String toName = i.toString();

                subNodes[toName] = subNodes.remove(fromName)
                  ..renameReference(fromName, toName, this);
              }
            }
          }
          if (lc.addedCount > 0) {
            // Fix path on tail
            // NOTE : use subnodes length because that was the length when the change occurred
            // This is relevant when more than one change ad a time are given
            if (adjust > 0) {
              for (int i = subNodes.length - 1; i >= lc.index; i--) {
                String fromName = i.toString();
                String toName = (i + adjust).toString();

                subNodes[toName] = subNodes.remove(fromName)
                  ..renameReference(fromName, toName, this);
              }
            }

            // Add new observers
            for (int i = lc.index; i < lc.addedCount + lc.index; i++) {
              HasParentMixin child = new PropertyNotifier.from(target[i]);
              if (child == null) {
                child = new FakeSubNode();
              }
              if (child != null) {
                subNodes[i.toString()] = child
                  ..addReference(i.toString(), this);
              }
            }
          }

          // Notify
          return new SpliceData(lc.index, lc.addedCount, lc.removed);
        }).toList();
        notifySplice("splices", splicesData);
        //_logger.fine("END PROCESSING CHANGES");
        new ChangeVersion(convertToJs(_target)).comingFromJS =
            false; // Reset Flag
      });
    }
  }

  Map discoverChildren(_target) {
    return new Map.fromIterable(
        new List.generate(_target.length, (int index) => index),
        key: (int index) => index.toString(),
        value: (int index) => _target[index]);
  }

  void destroy() {
    if (_sub != null) {
      _sub.cancel();
    }
    destroyChildren();
    PropertyNotifier.evict(_target);
  }
}

class FakeSubNode extends Object with HasParentMixin {
  void destroy() {

  }
}

@BehaviorProxy('Polymer.Dart.AutoNotify.Behavior')
@deprecated
abstract class PolymerAutoNotifySupportJsBehavior {
  // Needed to be sure the behavior get initialized.
  var js = DartAutonotifyJS;
}

@behavior
@deprecated
abstract class PolymerAutoNotifySupportBehavior
    implements PolymerAutoNotifySupportJsBehavior {}

// Alternative name for autonotify behavior
@BehaviorProxy('Polymer.Dart.AutoNotify.Behavior')
abstract class AutonotifyBehavior {
  // Needed to be sure the behavior get initialized.
  var js = DartAutonotifyJS;
}
