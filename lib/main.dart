// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Focus Order Demo',
      home: const Center(
        child: FocusTraversalDemo(),
      ),
    ),
  );
}

class RectData {
  const RectData(this.order, this.rect);

  @override
  int get hashCode {
    return hashValues(order, rect);
  }

  @override
  bool operator ==(dynamic other) {
    if (other is! RectData) {
      return false;
    }
    return order == other.order && rect == other.rect;
  }

  final int order;
  final Rect rect;

  @override
  String toString() {
    return '[$order: $rect]';
  }
}

class RectMap extends ChangeNotifier {
  RectMap(this._rects);

  int serial = 0;

  final Map<int, RectData> _rects;

  Map<int, RectData> toMap() => <int, RectData>{}..addAll(_rects);

  RectData operator [](int key) {
    return _rects[key];
  }

  RectData add(Rect rect) {
    serial++;
    final RectData newData = RectData(serial, rect);
    _rects[serial] = newData;
    _notify();
    return newData;
  }

  void operator []=(int key, RectData value) {
    _rects[key] = value;
    _notify();
  }

  RectData remove(int key) {
    final RectData result = _rects.remove(key);
    _notify();
    return result;
  }

  bool compareMaps(Map<int, RectData> orig, Map<int, RectData> replacement) {
    if (orig.length != replacement.length) {
      return false;
    }
    for (int key in orig.keys) {
      if (!replacement.containsKey(key)) {
        return false;
      }
      if (replacement[key] != orig[key]) {
        return false;
      }
    }
    return true;
  }

  void clear() {
    _rects.clear();
    _notify();
  }

  void replace(Map<int, RectData> replacement) {
    if (!compareMaps(_rects, replacement)) {
      _rects.clear();
      _rects.addAll(replacement);
      _notify();
    }
  }

  void _notify() {
    readingOrderSort();
    notifyListeners();
  }

  int get length => _rects.length;
  void readingOrderSort() {
    if (length <= 1) {
      return;
    }
    final List<_SortData> list = <_SortData>[];
    _rects.forEach((int id, RectData data) {
      list.add(_SortData(id, data));
    });

    final Iterable<_SortData> sortedList = _bandMethod(list);

    int order = 0;
    for (_SortData data in sortedList) {
      order++;
      _rects[data.id] = RectData(order, data.data.rect);
    }
  }

  // 1. Find the topmost top of the rectangles.
  // 2. Find the rectangle with the leftmost left side of those rectangles
  //    intersected by the topmost scaled by infinity in x (i.e. the vertical
  //    interval of the topmost).
  // 3. That's the starting widget.
  // 4. Find the leftmost widget in the band of that widget, and pick it as the
  //    next widget.
  // 6. The next widget is removed from the unplaced widgets and becomes the
  //    current widget,
  // 8. When there are no more unplaced widgets, go back to 1 to select a new
  //    top (since the previous ones have been removed).
  Iterable<_SortData> _bandMethod(List<_SortData> list) {
    Iterable<_SortData> inBand(_SortData current, Iterable<_SortData> candidates) {
      final Rect wide = Rect.fromLTRB(double.negativeInfinity, current.data.rect.top, double.infinity, current.data.rect.bottom);
      return candidates.where((_SortData item) {
        return !item.data.rect.intersect(wide).isEmpty;
      });
    }

    _SortData pickFirst(List<_SortData> candidates) {
      int compareLeftSide(_SortData a, _SortData b) {
        return a.data.rect.left.compareTo(b.data.rect.left);
      }
      int compareTopSide(_SortData a, _SortData b) {
        return a.data.rect.top.compareTo(b.data.rect.top);
      }
      // Get the topmost
      candidates.sort(compareTopSide);
      final _SortData topmost = candidates.first;
      // If there are any others in the band of the topmost, then pick the
      // leftmost one.
      final List<_SortData> inBandOfTop = inBand(topmost, candidates).toList();
      inBandOfTop.sort(compareLeftSide);
      if (inBandOfTop.isNotEmpty) {
        return inBandOfTop.first;
      }
      return topmost;
    }

    // Pick the initial widget as the one that is leftmost in the band of the
    // topmost, or the topmost, if there are no others in its band.
    final List<_SortData> sortedList = <_SortData>[];
    final List<_SortData> unplaced = list.toList();
    _SortData current = pickFirst(unplaced);
    sortedList.add(current);
    unplaced.remove(current);

    while (unplaced.isNotEmpty) {
      final _SortData next = pickFirst(unplaced);
      current = next;
      sortedList.add(current);
      unplaced.remove(current);
    }

    return sortedList;
  }

  void clampToGrid() {
    const double gridSize = 10.0;
    double grid(double value) {
      return (value / gridSize).roundToDouble() * gridSize;
    }

    for (int key in _rects.keys) {
      final Rect gridRect = Rect.fromLTRB(
        grid(_rects[key].rect.left),
        grid(_rects[key].rect.top),
        grid(_rects[key].rect.right),
        grid(_rects[key].rect.bottom),
      );
      _rects[key] = RectData(_rects[key].order, gridRect);
    }
    _notify();
  }
}

double yScale = 4.0;

RectMap model = RectMap(<int, RectData>{});

abstract class RectDataTrackerWidget extends StatefulWidget {
  const RectDataTrackerWidget({Key key, this.id}) : super(key: key);

  final int id;
}

class BoxHandles extends RectDataTrackerWidget {
  const BoxHandles({Key key, int id, this.onRectChanged}) : super(key: key, id: id);

  final ValueChanged<Rect> onRectChanged;

  @override
  _BoxHandlesState createState() => _BoxHandlesState();
}

class _BoxHandlesState extends State<BoxHandles> {
  void dragHandle(DragUpdateDetails details) {
    setState(() {
      final Rect rect = Rect.fromPoints(
        model[widget.id].rect.topLeft,
        model[widget.id].rect.bottomRight + details.delta,
      );
      if (widget.onRectChanged != null) {
        widget.onRectChanged(rect);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Offset origin = Offset(model[widget.id].rect.size.width - 30, model[widget.id].rect.size.height - 30);
    final Rect handleRect = Rect.fromPoints(origin, origin + const Offset(30, 30));
    return Positioned.fromRect(
      rect: handleRect,
      child: GestureDetector(
        onPanEnd: (DragEndDetails _) => model.clampToGrid(),
        onPanUpdate: dragHandle,
        child: Container(color: Colors.green),
      ),
    );
  }
}

class FocusableBox extends RectDataTrackerWidget {
  const FocusableBox({
    Key key,
    @required int id,
  }) : super(key: key, id: id);

  @override
  _FocusableBoxState createState() => _FocusableBoxState();
}

class _FocusableBoxState extends State<FocusableBox> {
  void _dragRect(DragUpdateDetails details) {
    final Rect newRect = Rect.fromPoints(
      model[widget.id].rect.topLeft + details.delta,
      model[widget.id].rect.bottomRight + details.delta,
    );
    model[widget.id] = RectData(model[widget.id].order, newRect);
  }

  void _resized(Rect newRect) {
    setState(() {
      final double left = math.max(newRect.left, model[widget.id].rect.left);
      final double top = math.max(newRect.top, model[widget.id].rect.top);
      final Rect clampedRect = Rect.fromLTRB(
        left,
        top,
        math.max(left + 20.0, newRect.right),
        math.max(top + 20.0, newRect.bottom),
      );
      model[widget.id] = RectData(model[widget.id].order, clampedRect);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: model[widget.id].rect,
      child: Stack(
        children: <Widget>[
          GestureDetector(
            onPanUpdate: _dragRect,
            onPanEnd: (DragEndDetails _) => model.clampToGrid(),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 1.0),
              ),
              child: Center(child: Text('${model[widget.id].order}')),
            ),
          ),
          BoxHandles(id: widget.id, onRectChanged: _resized),
          Positioned.fromRect(
            rect: Rect.fromLTWH(model[widget.id].rect.size.width - 22, 0, 20, 20),
            child: GestureDetector(
              onTap: () {
                model.remove(widget.id);
              },
              child: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

class BoxCanvas extends StatefulWidget {
  @override
  _BoxCanvasState createState() => _BoxCanvasState();
}

class _BoxCanvasState extends State<BoxCanvas> {
  int length = 0;

  void updateRects() {
    if (length != model.length) {
      setState(() {
        length = model.length;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    length = model.length;
    model.addListener(updateRects);
  }

  @override
  void dispose() {
    model.removeListener(updateRects);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<int, FocusableBox> boxes = model.toMap().map<int, FocusableBox>((int index, RectData data) {
      return MapEntry<int, FocusableBox>(index, FocusableBox(id: index));
    });
    return Stack(children: boxes.values.toList());
  }
}

class FocusTraversalDemo extends StatefulWidget {
  const FocusTraversalDemo({Key key}) : super(key: key);

  @override
  _FocusTraversalDemoState createState() => _FocusTraversalDemoState();
}

class _SortData {
  _SortData(this.id, this.data) : newOrder = data.order;
  int id;
  RectData data;
  int newOrder;

  @override
  String toString() {
    return '[order: ${data.order}, rect: (${data.rect.left.toStringAsFixed(1)}, ${data.rect.top.toStringAsFixed(1)}, ${data.rect.right.toStringAsFixed(1)}, ${data.rect.bottom.toStringAsFixed(1)})]';
  }
}

class _FocusTraversalDemoState extends State<FocusTraversalDemo> {
  @override
  void initState() {
    super.initState();
    _loadBaseModel();
    model.addListener(() => setState(() {}));
  }

  void _loadBaseModel() {
    model.clear();
    const Offset origin = Offset(60.0, 60.0);
    const double radius = 50.0;
    const double stride = radius * 2.0 + 20.0;
    for (int i = 0; i< 2; i++) {
      for (int j = 0; j< 3; j++) {
        model.add(Rect.fromCircle(center: Offset(stride * j, stride * i) + origin, radius: 50));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Focus Order Demo'),
          actions: <Widget>[
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _loadBaseModel();
                })
          ],
        ),
        body: DefaultTextStyle(
          style: textTheme.display1,
          child: BoxCanvas(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              model.add(Rect.fromCircle(center: const Offset(200, 300), radius: 50));
            });
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
