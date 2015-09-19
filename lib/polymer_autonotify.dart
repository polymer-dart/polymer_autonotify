library elys.auto_notify;

import "package:polymer/polymer.dart";
import "package:observe/observe.dart";
import "package:smoke/smoke.dart";
import "package:logging/logging.dart";
import "dart:async";



abstract class NotifierNode {
  static final Map _notifiersCache = {};



  bool notifyPath(String name,var newValue);
  notifySplice(List array, String path, int index, int added, List removed);

  NotifierNode() {

  }

  factory NotifierNode.fromTarget(target) {
    NotifierNode n = _notifiersCache[target];
    if (n==null) {
      if (target is PolymerElement) {
        n = new NotifierNodeRoot(target);
      } else if (target is Observable) {
        n = new NotifierObservableSubNode(target);
      } else if (target is List) {
        n = new NotifierListSubNode(target);
      } else {
        return null;
      }
      _notifiersCache[target] = n;
    }
    return n;
  }

  void destroy();

  static NotifierNode evict(target) => _notifiersCache.remove(target);
}

abstract class HasChildrenMixin implements NotifierNode {
  Map<String,HasParentMixin> subNodes = {};

  void addChildren(target) {
    Map children = discoverChildren(target);
    children.forEach((String name,subTarget) {
      HasParentMixin prev = subNodes.remove(name);
      if (prev!=null) {
        prev.removeReference(name,this);
      }


      HasParentMixin child = new NotifierNode.fromTarget(subTarget);
      if (child!=null) {
        subNodes[subTarget] = child
          ..addReference(name, this);
      }

    });
  }



  Map discoverChildren(target);


  void destroyChildren() {
    subNodes.forEach((String name,HasParentMixin child){
      child.removeReference(name,this);
    });
    subNodes.clear();
  }

}

abstract class HasParentMixin implements NotifierNode {
  Map<String,List<HasChildrenMixin>> parents={};

  void removeReference(String name,HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents[name];
    if (refs!=null) {
      refs.remove(parent);
      if (refs.length==0) {
        refs.remove(name);
      }
    }
    if (parents.isEmpty) {
      // no reason to exist if no one references me
      destroy();
    }
  }

  void addReference(String name, HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents.putIfAbsent(name,() => new List());
    refs.add(parent);
  }

  void renameReference(String fromName,String toName, HasChildrenMixin parent) {
    List<HasChildrenMixin> refs = parents[fromName];
    if (refs!=null) {
      refs.remove(parent);
      if (refs.length==0) {
        refs.remove(fromName);
      }
    }
    refs = parents.putIfAbsent(toName,ifAbsent:() => new List());
    refs.add(parent);

  }

  bool notifyPath(String name, newValue) {
    parents.forEach((String parentName,List<NotifierNode> parents1) {
      parents1.forEach((NotifierNode parent) {
        parent.notifyPath(parentName+"."+name,newValue);
      });
    });
  }

  notifySplice(List array, String path, int index, int added, List removed) {
    parents.forEach((String parentName,List<NotifierNode> parents1) {
      parents1.forEach((NotifierNode parent) {
        parent.notifySplice(array,path!=null? parentName+"."+path: parentName,index,added,removed);
      });
    });
  }
}

abstract class HasChildrenReflectiveMixin implements HasChildrenMixin {

  Map discoverChildren(target) {
    List<Declaration> fields = query(target.runtimeType,new QueryOptions(includeFields:true,includeProperties:true,includeInherited:false));
    return new Map.fromIterable(fields.where((Declaration f) => f.annotations.any((a)=> a is ObservableProperty)),
      key:(Declaration f) => symbolToName(f.name),
      value:(Declaration f) => read(target,f.name));
  }

  StreamSubscription _sub;

  init(Observable _target) {
    addChildren(_target);
    _sub=observe(_target);
  }

  StreamSubscription observe(Observable target) {
    // Attach listener too
    return target.changes.listen((List<ChangeRecord> recs) {
      recs.where((ChangeRecord cr) => cr is PropertyChangeRecord).forEach((PropertyChangeRecord pcr) {
        String name = symbolToName(pcr.name);
        var val = pcr.newValue;
        notifyPath(name,val);

        // Replace observer
        HasParentMixin child = subNodes.remove(name);
        if (child!=null) {
          child.removeReference(name,this);
        }

        child = new NotifierNode.fromTarget(val);
        if (child!=null) {
          subNodes[name] = child
            ..addReference(name,this);
        }

      });
    });
  }

  void cleanUpListener() {
    _sub.cancel();

  }


}

class NotifierNodeRoot extends NotifierNode with HasChildrenMixin, HasChildrenReflectiveMixin {
  PolymerElement _element;

  NotifierNodeRoot(PolymerElement element) {
    _element = element;
    if (!(element is Observable)) {
      throw "Using notifier on non observable Polymer";
    }
    init(_element);
  }

  bool notifyPath(String name, newValue) {
    print ("${_element} NOTIFY ${name} with ${newValue}");
    return _element.notifyPath(name, newValue);
  }

  notifySplice(List array, String path, int index, int added, List removed) {
    print ("${_element} NOTIFY SPLICE OF ${path} at ${index}");
    return _element.jsElement.callMethod('_notifySplice', [jsValue(array), path, index, added, jsValue(removed)]);
  }

  void destroy() {
    cleanUpListener();
    destroyChildren();
    NotifierNode.evict(_element);
  }


}

class NotifierObservableSubNode extends NotifierNode with HasParentMixin, HasChildrenMixin,HasChildrenReflectiveMixin {

  Observable _target;

  NotifierObservableSubNode(Observable target) {
    _target = target;
    init(_target);
  }

  void destroy() {
    cleanUpListener();
    destroyChildren();
    NotifierNode.evict(_element);
  }


}

class NotifierListSubNode extends NotifierNode with HasParentMixin,HasChildrenMixin {

  List _target;
  StreamSubscription _sub;

  NotifierListSubNode(List target) {
    _target = target;
    addChildren(_target);

    if (_target is ObservableList) {
      // Observe changes on list too
      _sub = (target as ObservableList).listChanges.listen((List<ListChangeRecord> rc) {
        // Notify splice
        rc.forEach((ListChangeRecord lc) {
          notifySplice(_target, null, lc.index, lc.addedCount, lc.removed);

          // Adjust references

          // Fix observers
          if(lc.removed!=null) {
            for(int i=0;i<lc.removed.length;i++) {
              String name = (lc.index+i).toString();
              subNodes.remove(name).removeReference(name,this);
            }

            // fix path on the rest
            for (int i=lc.index;i<target.length;i++) {
              String fromName = (i+lc.removed.length).toString();
              String toName = i.toString();

              _subNotifiers[toName]=_subNotifiers.remove(fromName)
                ..renameReference(fromName,toName,this);

            }

          }
          if (lc.addedCount>0) {
            // Fix path on tail
            for (int i=lc.index+lc.addedCount;i<target.length;i++) {
              String fromName = (i-lc.addedCount).toString();
              String toName = i.toString();

              _subNotifiers[toName] =_subNotifiers.remove(fromName)
                ..renameReference(fromName,toName,this);
            }

            // Add new observers
            for (int i=lc.index;i<lc.addedCount+lc.index;i++) {
              if (target[i] is Observable || target[i] is ObservableList) {
                HasParentMixin child = new NotifierNode.fromTarget(target[i]);
                if (child!=null) {
                  subNodes[i.toString()] = child
                    ..addReference(i.toString(),this);
                }
              }
            }
          }
        });
      });
    }

  }

  Map discoverChildren(_target) {
    return new Map.fromIterable(new List.generate(_target.length,(int index) => index),
      key:(int index) => index.toString(),
      value: (int index) => _target[index]);
  }

  void destroy() {
    if (_sub!=null) {
      _sub.cancel();
    }
    destroyChildren();
    NotifierNode.evict(_element);

  }


}


class ObservablePolymerNotifier {

  static final Logger _logger = new Logger("polymer.auto.notify");

  String _path="";
  PolymerElement _element;
  Observable _target;
  StreamSubscription _sub;

  Map<String,ObservablePolymerNotifier> _subNotifiers = {};

  ObservablePolymerNotifier(PolymerElement element, var target,[String path=""]) {
    _element = element;
    _path = path;
    _target = target;

    if (target is Observable) {
      _sub = target.changes.listen((List<ChangeRecord> recs) {
        recs.where((ChangeRecord cr) => cr is PropertyChangeRecord).forEach((PropertyChangeRecord pcr) {
          var val = pcr.newValue;
          _notifySymbol(symbolToName(pcr.name), val);
        });
      });
    } else if (target is ObservableList) {
      _sub = (target as ObservableList).listChanges.listen((List<ListChangeRecord> rc){

        // Notify splice
        rc.forEach((ListChangeRecord lc) {

          _notifySplice(target,"${_path}${symbolToName(pcr.name)}",lc.index,lc.addedCount,lc.removed);
          // Fix observers
          if(lc.removed!=null) {
            for(int i=0;i<lc.removed.length;i++) {
              _subNotifiers.remove((lc.index+i).toString()).close();
            }
            // fix path on the rest
            for (int i=lc.index;i<target.length;i++) {
              _subNotifiers[i.toString()]=_subNotifiers.remove((i+lc.removed.length).toString())
                .._path="${_path}${symbolToName(pcr.name)}.${i}";
            }

          }
          if (lc.addedCount>0) {
            // Fix path on tail
            for (int i=lc.index+lc.addedCount;i<target.length;i++) {
              _subNotifiers[i.toString()] =_subNotifiers.remove((i-lc.addedCount).toString())
                .._path="${_path}${symbolToName(pcr.name)}.${i}";
            }

            // Add new observers
            for (int i=lc.index;i<lc.addedCount+lc.index;i++) {
              _notifySymbol(i.toString(),target[i]);
            }
          }


        });

      });
    }

    // Add Sub

    if (target is List) {
      for (int i=0;i<target.length;i++) {
        _notifySplice(target,"${_path}".substring(0,_path.length-1),0,target.length,target);
        _notifySymbol(i.toString(),target[i],true);
      }
    } else {
      List<Declaration> fields = query(target.runtimeType,new QueryOptions(includeFields:true,includeProperties:true,includeInherited:false));
      fields.where((Declaration f) => f.annotations.any((a)=> a is ObservableProperty)).forEach((Declaration f) {
        var fieldValue=read(target,f.name);
        _notifySymbol(symbolToName(f.name),fieldValue);
      });
    }
  }

  void _notifySymbol(String name,var value,[bool onlyInstall=false]) {
    String path = "${_path}${name}";
    if (!onlyInstall) {
      _logger.fine("Notify ${path} with ${value} for ${_element}");
      if (value!=null)
      _element.notifyPath(path,value);
    }
    _installSubNotifier(name,value);
  }

  void _installSubNotifier(String name,var target) {
    // Attach a new sub notifier for observable objects

    ObservablePolymerNotifier subNotifier = _subNotifiers[name];
    if (subNotifier!=null) {
      subNotifier.close();
    }
    String subPath = "${_path}${name}";
    if (target!=null && (target is Observable || target is List)) {
      _logger.fine("Installing subnotifier for ${name} with ${target}");
      subNotifier = new ObservablePolymerNotifier(_element,target,"${subPath}.");
      _subNotifiers[name] = subNotifier;
    }

  }

  void  close() {
    _subNotifiers.values.forEach((ObservablePolymerNotifier x) => x.close());
    _subNotifiers.clear();
    if (_sub!=null) {
      _sub.cancel();
      _sub=null;
    }
  }


  void _notifySplice(List array, String path, int index, int added, List removed) =>
    _element.jsElement.callMethod('_notifySplice', [jsValue(array),path,index,added, jsValue(removed)]);


}

@behavior
abstract class PolymerAutoNotifySupportMixin  {
  //ObservablePolymerNotifier _observablePolymerNotifier;

  NotifierNodeRoot _rootNotifier;

  static created(mixin) {
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!! MIXIN CREATED CALLED !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
  }

  void attached() {
    //_observablePolymerNotifier = new ObservablePolymerNotifier(this,this);
    _rootNotifier = new NotifierNode.fromTarget(this);
  }

  void detached() {
    //_observablePolymerNotifier.close();
    //_observablePolymerNotifier=null;
    _rootNotifier.destroy();
  }

}