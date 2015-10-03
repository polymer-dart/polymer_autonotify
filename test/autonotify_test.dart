@TestOn('browser')
library polymer_autonotify.tests;

import 'dart:async';
import 'dart:html';
import 'package:polymer/polymer.dart';
import 'package:test/test.dart';

import "package:web_components/web_components.dart" show HtmlImport;
import "package:observe/observe.dart";
import "package:polymer_autonotify/polymer_autonotify.dart";

import "package:logging/logging.dart";

import "dart:js";

TestMain element;
TestElement subElement1;
TestElement subElement2;

int counter = 0;


main() async {
  print("ATTENDO");
  await initPolymer();

  print ("PoLYMER READY");
  setUp(() {
    element = document.createElement('test-main');
    //document.body.append(element);
    List<Element> subs = Polymer.dom(element.root).querySelectorAll("test-element");
    subElement1=subs[0];
    subElement2=subs[1];
  });

  test('sanity check', () {
    expect(element,isNotNull);
    expect(subElement1,isNotNull);
    expect(subElement2,isNotNull);
  });

  group('generic tests',() {
    test('add elements',() async {
      //element.add("samples",new Sample("X","Y"));

      element.samples.add(new Sample("X1","Y1"));
      element.samples.add(new Sample("X2","Y2"));
      element.samples.add(new Sample("X3","Y3"));
      await new Future.delayed(new Duration(milliseconds:200));
      //await new Future.value(true);
      DivElement elem1 = Polymer.dom(subElement1.root).querySelector("[data-marker='0']");
      //print(subElement1.outerHtml);
      expect(elem1,isNotNull);
      expect(elem1.attributes["f1"],"X1");
      expect(elem1.attributes["f2"],"Y1");

      DivElement elem2 = Polymer.dom(subElement2.root).querySelector("[data-marker='1']");
      //print(subElement1.outerHtml);
      expect(elem2,isNotNull);
      expect(elem2.attributes["f1"],"X2");
      expect(elem2.attributes["f2"],"Y2");
    });

    test('update element',() async {
      //element.add("samples",new Sample("X","Y"));

      element.samples[1].field1="alpha1";


      await new Future.delayed(new Duration(milliseconds:500));
      //await new Future.value(true);
      DivElement elem1 = Polymer.dom(subElement1.root).querySelector("[data-marker='1']");
      print(subElement1.outerHtml);
      expect(elem1,isNotNull);
      expect(elem1.attributes["f1"],"alpha1");
      expect(elem1.attributes["f2"],"Y1");
    });
  });
}



class Sample extends Observable {

  @observable String field1;
  @observable String field2;

  Sample(this.field1,this.field2);

  String toString() => "S(${field1};${field2})";
}

@PolymerRegister("test-element")
class TestElement extends PolymerElement   with Observable , PolymerAutoNotifySupportJsBehavior, PolymerAutoNotifySupportBehavior {
  static final Logger _logger = new Logger("test.element.TestElement");

  @observable @property List<Sample> samples;

  @observable @Property(notify:true) String message;

  @observable @Property(notify:true) String message2;


  TestElement.created() : super.created() {
  //  PolymerAutoNotifySupportJsBehavior, PolymerAutoNotifySupportBehavior.created(this);
  }

  factory TestElement() => (new Element.tag("test-element") as TestElement);

}

class Holder extends Observable {
  @observable String message="OK";
  Holder(this.message);
}

@PolymerRegister("test-main")
class TestMain extends PolymerElement   with Observable, PolymerAutoNotifySupportJsBehavior, PolymerAutoNotifySupportBehavior {
  static final Logger _logger = new Logger("test.element.TestMain");

  @observable @property List<Sample> samples = new ObservableList();
  @observable @Property(notify:true) String message="OK";
  @observable @Property(notify:true) Holder message2= new Holder("KO");

  @property int step=1;

  @reflectable
  String clickMe([_,__]) {
    print("CLICKED");
    samples.insert(1,new Sample("ciao${counter++}","ciao${counter++}"));
  }

  @reflectable
  void removeMe([_,__]) {
    if (samples.isNotEmpty) {
      samples.removeAt(0);
    }
  }

  @reflectable
  void removeMe2([_,__]) {
    removeAt("samples",0);
  }

  @reflectable
  void addInitial([_,__]) {
    samples.addAll([
      new Sample("1,1","1,2"),
      new Sample("2,1","2,2")
    ]);
  }

  @reflectable
  void updateMe([_,__]) {
    samples[1].field1="CHANGED";
    print("CHANGED");
  }

  @reflectable
  void updateMe2([_,__]) {
    set("samples.1.field1","CHANGED");
  }

  @reflectable
  void addEnd([_,__]) {
    samples.add(new Sample(message,message2.message));
  }

  @reflectable
  void addEnd2([_,__]) {
    add("samples",new Sample("ciao${counter++}","ciao${counter++}"));
  }

  @reflectable
  void removeEnd([_,__]) {
    samples.removeLast();
  }

  @Observe("samples.splices")
  void samplesChanged(splices) {
    _logger.fine("SAMPLES CHANGED :${splices}");
  }

  @reflectable
  void replaceOne([_,__]) {
    samples[1]=new Sample("REPLACED","REPLACED");
  }

  @reflectable
  void testSome([_,__]) {
    var list = new ObservableList.from(["a","b","c"])
      ..listChanges.listen((List<ListChangeRecord> changes) {
        changes.forEach((ListChangeRecord rec) {
          print("CHANGED :${rec}");
        });
    });
    JsArray js =new JsArray.from(list);
    js.callMethod("splice",[1,0,"d"]);
    print("JS FINAL : ${js}");
    print("LIST FINALE :${list}");
  }

  @reflectable
  void addMe2([_,__]) {
    insert("samples",1,new Sample("banana-${counter++}","papaghena-${counter++}"));
  }

  @reflectable
  void doMany([_,__]) {
    [
      () => addEnd2(),
          () => addEnd2(),
          () => addEnd2(),
          () => updateMe2(),
          () => removeMe2(),
          () => updateMe2()
    ][step-1]();

    set("step",step+1);

  }

  TestMain.created() : super.created() {
   // PolymerAutoNotifySupportJsBehavior, PolymerAutoNotifySupportBehavior.created(this);
  }

  factory TestMain() => (new Element.tag("test-main") as TestMain);

}
