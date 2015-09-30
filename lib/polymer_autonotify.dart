@HtmlImport('polymer_autonotify.html')
library autonotify.support;

import "package:polymer/polymer.dart";
import "package:web_components/web_components.dart" show HtmlImport;
import "package:observe/observe.dart";
import "package:smoke/smoke.dart";
import "package:logging/logging.dart";
import "dart:async";
import "dart:js";
import "package:polymer/init.dart" show polymerDartSyncDisabled;

Logger _logger = new Logger("autonotify.support");


final JsObject DartAutonotifyJS = () {
  JsObject j = context["Polymer"]["Dart"]["AutoNotify"];
  j["updateJsVersion"] = (js) {
    List dart = convertToDart(js);
    ChangeVersion jsChange = new ChangeVersion(js);
    ChangeVersion dartChange = new ChangeVersion(dart);
    jsChange.version=dartChange.version+1;
  };

  return j;
}();


abstract class PropertyNotifier {
  static final Expando<PropertyNotifier> _notifiersCache = new Expando();
  static final Map _cycleDetection = {};

  bool notifyPath(String name, var newValue);
  notifySplice(List array, String path, int index, int added, List removed);

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
          if (target is PolymerElement) {
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
    Map children = discoverChildren(target);
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

  Map discoverChildren(target);

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

  notifySplice(List array, String path, int index, int added, List removed) {
    parents.forEach((String parentName, List<PropertyNotifier> parents1) {
      parents1.forEach((PropertyNotifier parent) {
        parent.notifySplice(
            array,
            path != null ? parentName + "." + path : parentName,
            index,
            added,
            removed);
      });
    });
  }
}

abstract class HasChildrenReflectiveMixin implements HasChildrenMixin {
  Map discoverChildren(target) {
    List<Declaration> fields = query(
        target.runtimeType,
        new QueryOptions(
            includeFields: true,
            includeProperties: true,
            includeInherited: false,
            withAnnotations: [ObservableProperty]));
    return new Map.fromIterable(fields,
        key: (Declaration f) => symbolToName(f.name),
        value: (Declaration f) => read(target, f.name));
  }

  StreamSubscription _sub;

  init(Observable _target) {
    addChildren(_target);
    _sub = observe(_target);
  }

  findDartTarget(String name) {
    List<String> p = name.split(".");
    String last = p.removeLast();
    String before = p.join(".");
    var tgt;
    if (p.length > 0) {
      tgt = _element.get(before);
    } else {
      tgt = _element;
    }
    return tgt;
  }

  StreamSubscription observe(Observable target) {
    // Attach listener too
    return target.changes.listen((List<ChangeRecord> recs) {
      Map newValues = {};
      recs.where((ChangeRecord cr) => cr is PropertyChangeRecord).forEach(
          (PropertyChangeRecord pcr) => newValues[pcr.name] = pcr.newValue);

      newValues.forEach((Symbol sym, val) {
        String name = symbolToName(sym);
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

class PolymerElementPropertyNotifier extends PropertyNotifier
    with HasChildrenMixin, HasChildrenReflectiveMixin {
  PolymerElement _element;
  //Expando<ChangeVersion> _notifyVersionTrackingExpando = new Expando();

  PolymerElementPropertyNotifier(PolymerElement element) {
    _element = element;
    if (!(element is Observable)) {
      throw "Using notifier on non observable Polymer";
    }
    init(_element);
  }

  bool notifyPath(String name, newValue) {
    if (_logger.isLoggable(Level.FINE)) {
      _logger.fine("${_element} NOTIFY ${name} with ${newValue}");
    }
    // Sync'em

    return _element.set(name, newValue);
  }

  notifySplice(List array, String path, int index, int added, List removed) {
    JsArray js = convertToJs(array);
    ChangeVersion jsVersion = new ChangeVersion(js);
    ChangeVersion dartVersion = new ChangeVersion(array);

    // Sync'em
    if (jsVersion.version != dartVersion.version) {

      jsVersion.version = dartVersion.version;

      try {
        DartAutonotifyJS["ignoreNextSplice"] = true;
        js.callMethod("splice",[index,removed.length]..addAll(array.sublist(index,index+added).map(convertToJs)));
        _element.jsElement.callMethod("_notifySplice",[js,path,index,added,removed.map(convertToJs).toList()]);

      } finally {
        // just in case something weird happens ..
        DartAutonotifyJS["ignoreNextSplice"] = false;
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
        // Notify splice
        rc.forEach((ListChangeRecord lc) {
          // Avoid loops when splicing jsArray
          new ChangeVersion(_target).version++;

          notifySplice(_target, null, lc.index, lc.addedCount, lc.removed);
          // Adjust references

          // Fix observers
          if (lc.removed != null && lc.removed.length > 0) {
            for (int i = 0; i < lc.removed.length; i++) {
              String name = (lc.index + i).toString();
              subNodes.remove(name).removeReference(name, this);
            }

            // fix path on the rest
            for (int i = lc.index; i < target.length-lc.addedCount; i++) {
              String fromName = (i + lc.removed.length).toString();
              String toName = i.toString();

              subNodes[toName] = subNodes.remove(fromName)
                ..renameReference(fromName, toName, this);
            }
          }
          if (lc.addedCount > 0) {
            // Fix path on tail
            for (int i = target.length - 1;
                i >= lc.index + lc.addedCount;
                i--) {
              String fromName = (i - lc.addedCount).toString();
              String toName = i.toString();

              subNodes[toName] = subNodes.remove(fromName)
                ..renameReference(fromName, toName, this);
            }

            // Add new observers
            for (int i = lc.index; i < lc.addedCount + lc.index; i++) {
              HasParentMixin child = new PropertyNotifier.from(target[i]);
              if (child != null) {
                subNodes[i.toString()] = child
                  ..addReference(i.toString(), this);
              }
            }
          }
        });
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

@BehaviorProxy('Polymer.Dart.AutoNotify.Behavior')
abstract class PolymerAutoNotifySupportJsBehavior {}

@behavior
abstract class PolymerAutoNotifySupportBehavior implements
    PolymerAutoNotifySupportJsBehavior,PolymerElement {
  PolymerElementPropertyNotifier _rootNotifier;

  static void created(PolymerAutoNotifySupportBehavior mixin) {
    mixin._rootNotifier = new PropertyNotifier.from(mixin);
    mixin.jsElement["isAutonotify"]=true;
  }

  static void detached(mixin) {
    mixin._rootNotifier.destroy();
  }
}
