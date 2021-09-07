import 'dart:io';

import 'package:bluebubbles/helpers/attachment_helper.dart';
import 'package:bluebubbles/helpers/constants.dart';
import 'package:bluebubbles/managers/settings_manager.dart';
import 'package:bluebubbles/repository/models/attachment.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';

class LocationWidget extends StatefulWidget {
  LocationWidget({
    Key? key,
    required this.file,
    required this.attachment,
  }) : super(key: key);
  final File file;
  final Attachment attachment;

  @override
  _LocationWidgetState createState() => _LocationWidgetState();
}

class _LocationWidgetState extends State<LocationWidget> with AutomaticKeepAliveClientMixin {
  AppleLocation? location;

  @override
  void initState() {
    super.initState();
    loadLocation();
  }

  void loadLocation() {
    // If we already have location data, don't load it again
    if (location != null) return;
    String _location = widget.file.readAsStringSync();
    location = AttachmentHelper.parseAppleLocation(_location);

    if (location != null && this.mounted) {
      setState(() {});
    }
  }

  void openMaps() async {
    if (location == null) return;

    await MapsLauncher.launchCoordinates(location!.longitude!, location!.latitude!);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (location != null &&
        location!.longitude != null &&
        location!.longitude!.abs() < 90 &&
        location!.latitude != null) {
      return GestureDetector(
          onTap: openMaps,
          child: Container(
              height: 240,
              color: Theme.of(context).accentColor,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                        height: 200,
                        child: FlutterMap(
                          options: MapOptions(
                            center: LatLng(location!.longitude!, location!.latitude!),
                            zoom: 14.0,
                          ),
                          layers: [
                            new TileLayerOptions(
                              urlTemplate: "http://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}",
                              subdomains: ['0', '1', '2', '3'],
                              tileSize: 256,
                            ),
                            new MarkerLayerOptions(
                              markers: [
                                new Marker(
                                  width: 40.0,
                                  height: 40.0,
                                  point: new LatLng(location!.longitude!, location!.latitude!),
                                  builder: (ctx) => new Container(
                                    child: Icon(SettingsManager().settings.skin.value == Skins.iOS ? CupertinoIcons.location : Icons.pin_drop, color: Colors.red, size: 45),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )),
                    InkWell(
                        onTap: openMaps,
                        child: Padding(
                            padding: EdgeInsets.only(top: 11, bottom: 10),
                            child: Text("Open in Maps", style: Theme.of(context).textTheme.bodyText1)))
                  ])));
    } else {
      return Container(
        padding: EdgeInsets.all(10),
        child: Text(
          "Could not load location",
          style: Theme.of(context).textTheme.bodyText1,
        ),
      );
    }
  }

  @override
  bool get wantKeepAlive => true;
}
