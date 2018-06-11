import 'dart:math';

import 'package:flutter/material.dart';
import 'package:music_player/bottom_controls.dart';
import 'package:music_player/songs.dart';
import 'package:music_player/theme.dart';
import 'package:fluttery/gestures.dart';
import 'package:fluttery_audio/fluttery_audio.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
        title: 'Flutter Demo',
        debugShowCheckedModeBanner: false,
        theme: new ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: new MyHomePage());
  }
}
class MyHomePage extends StatefulWidget{
  @override
  MyHomePageState createState() {
    return new MyHomePageState();
  }

}

class MyHomePageState extends State<MyHomePage> {

  @override
  Widget build(BuildContext context) {
    return new AudioPlaylist(
      playlist: demoPlaylist.songs.map((DemoSong song){
        return song.audioUrl;
      }).toList(growable: false),
      playbackState: PlaybackState.paused,
      child: new Scaffold(
          appBar: new AppBar(
            title: Text(''),
            backgroundColor: Colors.transparent,
            elevation: 0.0,
            leading: new IconButton(
              icon: new Icon(Icons.arrow_back_ios),
              onPressed: () {},
              color: const Color(0xFF000000),
            ),
            actions: <Widget>[
              new IconButton(
                icon: new Icon(Icons.menu),
                onPressed: () {},
                color: const Color(0xFF000000),
              ),
            ],
          ),
          body: new Column(
            children: <Widget>[
              //Seek Bar
              new Expanded(
                child: new AudioPlaylistComponent(
                  playlistBuilder: (BuildContext context, Playlist playlist, Widget child ){
                    String albumArtUrl = demoPlaylist.songs[playlist.activeIndex].albumArtUrl;
                    return new AudioRadialSeekBar(
                      albumArtUrl: albumArtUrl
                    );
                  })),
              //Visualizer
              new Container(
                width: double.infinity,
                height: 125.0,
                child: new Visualizer(
                  //FROM FLUTTERY - GETS Fourier Frecuency Distribution, Only works in Android
                  builder: (BuildContext context, List<int> fft){
                    //fft is a list coming from android, first two values are single values, the rest are value pairs and are the ones that matter
                    return new CustomPaint(
                      painter: new VisualizerPainter(
                        fft:    fft,
                        height: 125.0,
                        color: accentColor,
                      ),
                      child: new Container(),
                    );
                  })),

              //Song title, artist name, controls
              new BottomControls()
            ],
          )),
    );
  }
}

class VisualizerPainter extends CustomPainter {

  final List<int> fft;
  final double    height;
  final Color     color;
  final Paint     wavePaint;

  VisualizerPainter({
    this.fft,
    this.height,
    this.color
  }) : wavePaint = new Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    _renderWaves(canvas, size);
  }

  void _renderWaves(Canvas canvas, Size size){
    final histogramLow  = _createHistogram(fft, 15, 2                      ,((fft.length)/4).floor() );
    final histogramHigh = _createHistogram(fft, 15, ((fft.length)/4).ceil(),((fft.length)/2).floor()  );

    _renderHistogram(canvas, size, histogramLow );
    _renderHistogram(canvas, size, histogramHigh);
  }

  void _renderHistogram(Canvas canvas, Size size, List<int> histogram) {
    if(histogram.length == 0){
      return;
    }
    final pointsToGraph   = histogram.length;
    final widthPerSample = (size.width/(pointsToGraph-2)).floor();

    final points = new List<double>.filled(pointsToGraph*4, 0.0);

    for(int i = 0; i < histogram.length-1; ++i){
      points[i*4]   = (i*widthPerSample).toDouble();
      points[i*4+1] = size.height - histogram[i].toDouble();

      points[i*4+2] = ((i+1)*widthPerSample).toDouble();
      points[i*4+3] = size.height - histogram[i+1].toDouble();
    }
    
    Path path = new Path();
    path.moveTo(0.0, size.height);
    path.lineTo(points[0], points[1] );
    for(int i = 2; i < points.length-4; i+=2 ){
      path.cubicTo(
          points[i-2] + 10, points[i-1],
          points[i] - 10  , points[i+1],
          points[i]       , points[i+1],
      );
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, wavePaint);
  }

  List<int> _createHistogram(List<int> samples, int bucketCount, [int start, int end]  ){
    if(start == end){
      return const [];
    }
    start             = start ?? 0;
    end               = end   ?? samples.length -1;
    final sampleCount = end    - start + 1;

    final samplesPerBucket = (sampleCount / bucketCount).floor();
    if(samplesPerBucket == 0){
      return const [];
    }

    final actualSampleCount = sampleCount - (sampleCount % samplesPerBucket);
    List<int> histogram     = new List<int>.filled( bucketCount, 0 );

    //Add up the frequency amounts for each bucket.
    for(int i = start; i <= start+actualSampleCount; ++i   ){
      //Ignore the imaginary half of each FFT sample
      if((i - start) % 2 == 1){
        continue;
      }

      int bucketIndex = ((i - start) / samplesPerBucket).floor();
      histogram[bucketIndex] += samples[i];
    }

    //Message the data for Visualization
    for(var i = 0; i < histogram.length; i++){
      histogram[i] = (histogram[i] / samplesPerBucket).round();
    }

    return histogram;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

}

class AudioRadialSeekBar extends StatefulWidget{

  final String albumArtUrl;


  AudioRadialSeekBar({this.albumArtUrl});

  @override
  AudioRadialSeekBarState createState() {
    return new AudioRadialSeekBarState();
  }
}

class AudioRadialSeekBarState extends State<AudioRadialSeekBar> {

  double _seekPercent;

  @override
  Widget build(BuildContext context) {
    return new AudioComponent(
        updateMe: [
          WatchableAudioProperties.audioSeeking,
          WatchableAudioProperties.audioPlayhead,
        ],
        playerBuilder: (BuildContext context, AudioPlayer player, Widget child ){

          double playbackProgress = 0.0;
          if(player.audioLength != null && player.position != null){
            playbackProgress = player.position.inMilliseconds / player.audioLength.inMilliseconds;
          }

          _seekPercent = player.isSeeking ? _seekPercent : null;

          return new RadialSeekBar(
            progress:        playbackProgress,
            seekPercent:     _seekPercent,
            onSeekRequested: (double seekPercent) {
              setState(() {
                _seekPercent = seekPercent;
              });
              final seekMillis = (player.audioLength.inMilliseconds * seekPercent).round();
              player.seek(new Duration(milliseconds: seekMillis));
            },
            child: new Container(
              color: accentColor,
              child: new Image.network(
                widget.albumArtUrl,
                fit: BoxFit.cover,
              )
            )
          );
        });
  }
}

class RadialSeekBar extends StatefulWidget{

  final double           progress;
  final double           seekPercent;
  final Function(double) onSeekRequested;
  final Widget           child;

  RadialSeekBar({
    this.progress        = 0.0,
    this.seekPercent     = 0.0,
    this.onSeekRequested,
    this.child
  });

  @override
  RadialSeekBarState createState() {
    return new RadialSeekBarState();
  }
}

class RadialSeekBarState extends State<RadialSeekBar> {

  double     _progress = 0.0;
  PolarCoord _startDragCoord;
  double     _startDragPercent;
  double     _currentDragPercent;


  void _onDragStart(PolarCoord coord){
    _startDragCoord   = coord;
    _startDragPercent = _progress;

  }
  void _onDragUpdate(PolarCoord coord){
    final dragAngle   = coord.angle - _startDragCoord.angle;
    final dragPercent = dragAngle / (2*pi);
    setState(() {
      _currentDragPercent = (_startDragPercent + dragPercent)%1.0;
    });
  }
  void _onDragEnd(){

    if(widget.onSeekRequested != null){
      widget.onSeekRequested(_currentDragPercent);
    }

    setState(() {
      _currentDragPercent  = null;
      _startDragCoord      = null;
      _startDragPercent    = 0.0;
    });
  }

  RadialSeekBarState();


  @override
  Widget build(BuildContext context) {

    double thumbPosition = _progress;
    if(_currentDragPercent != null){
      thumbPosition = _currentDragPercent;
    }else if (widget.seekPercent!= null){
      thumbPosition = widget.seekPercent;
    }

    return new RadialDragGestureDetector(
        onRadialDragStart:  _onDragStart,
        onRadialDragUpdate: _onDragUpdate,
        onRadialDragEnd:    _onDragEnd,
        child: new Container(
            width  : double.infinity,
            height : double.infinity,
            color  : Colors.transparent, //We give it a color because in the abscence of color, touch events aren't processed
            child:   new Center(
                child: new Container(
                    width:  140.0,
                    height: 140.0,
                    child: new RadialProgressBar(
                        progressPercent: _progress,
                        progressColor:   accentColor,
                        thumbPosition:   thumbPosition,
                        thumbColor:      lightAccentColor,
                        innerPadding: const EdgeInsets.all(10.0),
                        outerPadding: const EdgeInsets.all(10.0),
                        child: new ClipOval(
                            clipper: new CircleClipper(),
                            child: widget.child,
                        )
                    )
                )
            )
        )
    );
  }

  @override
  void didUpdateWidget(RadialSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _progress = widget.progress;
  }

  @override
  void initState() {
    super.initState();
    _progress = widget.progress;
  }
}

class CircleClipper extends CustomClipper<Rect>{
  @override
  Rect getClip(Size size) {
    // TODO: implement getClip
    return new Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: min(size.width, size.height )/2
    );
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }

}

class RadialProgressBar extends StatefulWidget{
  final double     trackWidth;
  final Color      trackColor;
  final double     progressWidth;
  final Color      progressColor;
  final double     progressPercent;
  final double     thumbSize;
  final Color      thumbColor;
  final double     thumbPosition;
  final EdgeInsets outerPadding;
  final EdgeInsets innerPadding;
  final Widget     child;

  RadialProgressBar({
    this.trackWidth              = 3.0,
    this.trackColor              = Colors.grey,
    this.progressWidth           = 5.0,
    this.progressColor           = Colors.black,
    this.progressPercent         = 0.0,
    this.thumbSize               = 10.0,
    this.thumbColor              = Colors.black,
    this.thumbPosition           = 0.0,
    this.outerPadding            = const EdgeInsets.all(0.0),
    this.innerPadding            = const EdgeInsets.all(0.0),
    this.child
  });



  @override
  RadialProgressBarState createState() {
    return new RadialProgressBarState();
  }}

class RadialProgressBarState extends State <RadialProgressBar>{
  EdgeInsets _insetsForPainter(){
    //Make Room for thepaintedtrack, progress, and thumb
    //We divide by 2.0 because we want to allow flush painting
    //against the track so we only need to account the thickness outside the
    //track, not inside.
    final outerThickness = max(
      widget.trackWidth,
      max(
          widget.progressWidth,
          widget.thumbSize
      )
    ) / 2.0;
    return new EdgeInsets.all(outerThickness);
  }

  @override
  Widget build(BuildContext context) {
    return new Padding(
      padding: widget.outerPadding,
      child: new CustomPaint(
        //foegroundPainter paints on top of all in comparision with normal painter
        foregroundPainter: new RadialSeekBarPainter(
          trackWidth      : widget.trackWidth,
          trackColor      : widget.trackColor,
          progressWidth   : widget.progressWidth,
          progressColor   : widget.progressColor,
          progressPercent : widget.progressPercent,
          thumbSize       : widget.thumbSize,
          thumbColor      : widget.thumbColor,
          thumbPosition   : widget.thumbPosition,
        ),
        child: new Padding(
            padding: _insetsForPainter() + widget.innerPadding,

            child: widget.child
        ),
      ),
    );
  }
}

class RadialSeekBarPainter extends CustomPainter{

  final double trackWidth;
  final Paint  trackPaint;
  final double progressWidth;
  final Paint  progressPaint;
  final double progressPercent;
  final double thumbSize;
  final Paint  thumbPaint;
  final double thumbPosition;

  RadialSeekBarPainter({
    @required this.trackWidth      ,
    @required trackColor           ,
    @required this.progressWidth   ,
    @required progressColor        ,
    @required this.progressPercent ,
    @required this.thumbSize       ,
    @required thumbColor           ,
    @required this.thumbPosition
  }) :  trackPaint      = new Paint()
         ..color        = trackColor
         ..style        = PaintingStyle.stroke
         ..strokeWidth  = trackWidth,
        progressPaint   = new Paint()
          ..color       = progressColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth = progressWidth
          ..strokeCap   = StrokeCap.round,
        thumbPaint      = new Paint()
          ..color       = thumbColor
          ..style       = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {

    final outerThickness  = max(trackWidth, max(progressWidth, thumbSize));
    Size  constrainedSize = new Size(
        size.width  - outerThickness,
        size.height - outerThickness
    );

    final center = new Offset(size.width/2, size.height/2);
    final radius = min(size.width, size.height)/2;
    canvas.drawCircle(
      center,
      radius,
      trackPaint
    );

    //Paint Progress
    final progressAngle = 2* pi * progressPercent;
    canvas.drawArc(
        new Rect.fromCircle(
          center: center,
          radius: radius
        ),
        -pi/2,
        progressAngle,
        false,
        progressPaint
    );

    //Paint Thumb
    final thumbAngle  = 2 * pi * thumbPosition - (pi/2);
    final thumbX      = cos(thumbAngle) * radius;
    final thumbY      = sin(thumbAngle) * radius;
    final thumbCenter = new Offset(thumbX, thumbY)+center;
    final thumbRadius = thumbSize/2.0;
    canvas.drawCircle(
        thumbCenter,
        thumbRadius,
        thumbPaint
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

}