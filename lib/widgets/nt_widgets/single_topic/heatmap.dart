import 'package:elastic_dashboard/services/field_images.dart';
import 'package:flutter/material.dart';

import 'package:dot_cast/dot_cast.dart';
import 'package:provider/provider.dart';

import 'package:elastic_dashboard/widgets/nt_widgets/nt_widget.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class Heatmap extends NTWidget {
  static const String widgetType = 'heatmap';

  const Heatmap({super.key});

  final double lo = 525;
  final double bo = 100;
  final double ftToPixels = 2850 / 16.540988; //16.540988
  final double fieldWidth = 2850;
  final double fieldHeight = 8.069326 * (2850 / 16.540988);

  @override
  Widget build(BuildContext context) {
    SingleTopicNTWidgetModel model = cast(context.watch<NTWidgetModel>());

    return ValueListenableBuilder(
      valueListenable: model.subscription!,
      builder: (context, value, _) {
        List data = value?.cast<List>() ?? [];
        List<Widget> containerList = [];
        List objPoses = data.sublist(3);
        List objPosePairs = [];
        for (int i = 0; i < objPoses.length; i += 2) {
          objPosePairs.add([objPoses[i] * ftToPixels, objPoses[i + 1] * ftToPixels]);
        }

        int rows = 40;
        int columns = 80;
        int neighborRadius = 6;

        double maxDensity = 0;

        List<List> fieldBins = List<List>.generate(columns, (i) => List<double>.generate(rows, (j) => 0, growable: false), growable: false);

        for (List objPose in objPosePairs) {
          int xIndex = ((columns * objPose[0]) / fieldWidth).floor().clamp(0, columns-1);
          int yIndex = ((rows * objPose[1]) / fieldHeight).floor().clamp(0, rows-1);
          for (int i = -neighborRadius; i <= neighborRadius; i++) {
            if (xIndex + i > columns || xIndex + i < 0) {
              continue;
            }
            for (int j = -neighborRadius; j <= neighborRadius; j++) {
              if (yIndex + j > rows || yIndex + j < 0) {
                continue;
              }
              //fieldBins[xIndex + i][yIndex + j] += 1/(1 + i.abs() + j.abs());
              fieldBins[xIndex + i][yIndex + j] += 1/(1 + i.abs() + j.abs());
              if (fieldBins[xIndex + i][yIndex + j] > maxDensity) {
                maxDensity = fieldBins[xIndex + i][yIndex + j];
              }
            }
          }
        }

        for (final (x, row) in fieldBins.indexed) {
          for (final (y, density) in row.indexed) {
            if (density > 0) {
              containerList.add(
                Positioned(
                  left: lo + (x * fieldWidth / columns),
                  bottom: bo + (y * fieldHeight / rows),
                  child: Container(
                    width: fieldWidth / columns + 1,
                    height: fieldHeight / rows + 1,
                    decoration: BoxDecoration(
                      color: HSVColor.fromAHSV(
                          ((density / maxDensity) * 2).clamp(0, 1.0),
                          (1.0 - (density / maxDensity).clamp(0.0, 1.0)) * 240.0, 
                          1.0,
                          1.0
                        ).toColor(),
                      ),
                    ),
                ),
              );
            }
          }
        }

        /*
        for (int i = 0; i < objPoses.length; i += 2) {
          containerList.add(
            Positioned(
              left: lo + (objPoses[i] * ftToPixels) - 25,
              bottom: bo + (objPoses[i + 1] * ftToPixels) - 25,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          );
        }*/

        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              child: FittedBox(
                fit: BoxFit.contain,
                //child: Text(data, textAlign: TextAlign.center),
                child: Stack(
                  children: [
                    Container(
                      child: FieldImages.getFieldFromGame(
                        'Rebuilt (No Fuel)',
                      )?.fieldImage,
                    ),
                    ...containerList,
                    Positioned(
                      left: lo + (data[0] * ftToPixels) - 80,
                      bottom: bo + (data[1] * ftToPixels) - 80,
                      child: Transform.rotate(
                        angle: -data[2],
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 236, 150, 22),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: const Color.fromARGB(255, 132, 80, 17), width: 10),
                          ),
                          padding: EdgeInsets.all(40),
                          child: CustomPaint(
                            painter: TrianglePainter(
                              strokeWidth: 10
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color strokeColor;
  final PaintingStyle paintingStyle;
  final double strokeWidth;

  TrianglePainter({
    this.strokeColor = Colors.white,
    this.strokeWidth = 3,
    this.paintingStyle = PaintingStyle.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..style = paintingStyle;

    canvas.drawPath(getTrianglePath(size.width, size.height), paint);
  }

  Path getTrianglePath(double x, double y) => Path()
    ..moveTo(0, 0)
    ..lineTo(x, y / 2)
    ..lineTo(0, y)
    ..lineTo(0, 0)
    ..lineTo(x, y / 2);

  @override
  bool shouldRepaint(TrianglePainter oldDelegate) =>
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.paintingStyle != paintingStyle ||
      oldDelegate.strokeWidth != strokeWidth;
}