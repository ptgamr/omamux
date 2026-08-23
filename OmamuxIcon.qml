import QtQuick

Item {
  id: root

  property color paneColor: "#414a5b"
  property color accentColor: "#58d68d"
  property real contentScale: 1.0

  readonly property real iconSize: Math.min(width, height) * contentScale
  readonly property real leftEdge: (width - iconSize) / 2
  readonly property real topEdge: (height - iconSize) / 2

  Rectangle {
    x: root.leftEdge
    y: root.topEdge
    width: root.iconSize * 0.46
    height: root.iconSize * 0.56
    radius: root.iconSize * 0.08
    color: root.paneColor
  }

  Rectangle {
    x: root.leftEdge + root.iconSize * 0.54
    y: root.topEdge
    width: root.iconSize * 0.46
    height: root.iconSize * 0.56
    radius: root.iconSize * 0.08
    color: root.paneColor
  }

  Rectangle {
    x: root.leftEdge
    y: root.topEdge + root.iconSize * 0.65
    width: root.iconSize
    height: root.iconSize * 0.35
    radius: root.iconSize * 0.09
    color: root.accentColor

    Rectangle {
      x: parent.width * 0.10
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.20
      height: Math.max(1, parent.height * 0.28)
      radius: height / 2
      color: root.paneColor
    }
  }
}
