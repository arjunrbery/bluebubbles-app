import 'dart:async';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/group_event.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/message_content/message_attachments.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/received_message.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/sent_message.dart';
import 'package:bluebubbles/layouts/widgets/message_widget/sticker_widget.dart';
import 'package:bluebubbles/repository/models/attachment.dart';
import 'package:bluebubbles/repository/models/chat.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../../helpers/utils.dart';
import '../../../repository/models/message.dart';

class MessageWidget extends StatefulWidget {
  MessageWidget({
    Key key,
    this.fromSelf,
    this.message,
    this.chat,
    this.olderMessage,
    this.newerMessage,
    this.showHandle,
    this.customContent,
    this.shouldFadeIn,
    this.isFirstSentMessage,
    this.showHero,
    this.savedAttachmentData,
    this.offset,
    this.currentPlayingVideo,
    this.changeCurrentPlayingVideo,
    this.allAttachments,
  }) : super(key: key);

  final fromSelf;
  final Message message;
  final Chat chat;
  final Message newerMessage;
  final Message olderMessage;
  final bool showHandle;
  final bool shouldFadeIn;
  final bool isFirstSentMessage;
  final bool showHero;
  final SavedAttachmentData savedAttachmentData;
  final double offset;
  final Map<String, VideoPlayerController> currentPlayingVideo;
  final Function(Map<String, VideoPlayerController>) changeCurrentPlayingVideo;
  final List<Attachment> allAttachments;

  final List<Widget> customContent;

  @override
  _MessageState createState() => _MessageState();
}

class _MessageState extends State<MessageWidget> {
  List<Attachment> attachments = <Attachment>[];
  bool showTail = true;
  Widget blurredImage;
  List<Attachment> stickers = [];
  Completer<void> stickerRequest;

  @override
  void initState() {
    super.initState();
    fetchStickers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchStickers();
  }

  Future<void> fetchStickers() async {
    if (stickerRequest != null && !stickerRequest.isCompleted) return stickerRequest.future;
    stickerRequest = new Completer();

    widget.message.getAssociatedMessages().then((List<Message> messages) async {
      List<Message> tmp = messages
          .where((element) => element.associatedMessageType == "sticker")
          .toList();
      if (tmp.length > 0 && tmp.length != stickers.length) {
        stickers = [];
        for (Message msg in tmp) {
          if (!msg.hasAttachments) continue;
          List<Attachment> attachments = await Message.getAttachments(msg);
          stickers.addAll(attachments);
        }

        if (this.mounted) setState(() {});
        stickerRequest.complete();
      }
    });

    return stickerRequest.future;
  }

  bool withinTimeThreshold(Message first, Message second, {threshold: 5}) {
    if (first == null || second == null) return false;
    return second.dateCreated.difference(first.dateCreated).inMinutes.abs() >
        threshold;
  }

  Map<String, String> _buildTimeStamp(BuildContext context) {
    if (widget.newerMessage != null &&
        (!isEmptyString(widget.message.text) ||
            widget.message.hasAttachments) &&
        withinTimeThreshold(widget.message, widget.newerMessage,
            threshold: 30)) {
      DateTime timeOfnewerMessage = widget.newerMessage.dateCreated;
      String time = new DateFormat.jm().format(timeOfnewerMessage);
      String date;
      if (widget.newerMessage.dateCreated.isToday()) {
        date = "Today";
      } else if (widget.newerMessage.dateCreated.isYesterday()) {
        date = "Yesterday";
      } else {
        date =
            "${timeOfnewerMessage.month.toString()}/${timeOfnewerMessage.day.toString()}/${timeOfnewerMessage.year.toString()}";
      }
      return {"date": date, "time": time};
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.newerMessage != null) {
      showTail = withinTimeThreshold(widget.message, widget.newerMessage,
              threshold: 1) ||
          !sameSender(widget.message, widget.newerMessage) ||
          (widget.message.isFromMe &&
              widget.newerMessage.isFromMe &&
              widget.message.dateDelivered != null &&
              widget.newerMessage.dateDelivered == null);
    }

    if (widget.message != null &&
        isEmptyString(widget.message.text) &&
        !widget.message.hasAttachments) {
      return GroupEvent(
        message: widget.message,
      );
    } else {
      List<Widget> widgetStack = [];
      Widget widgetAttachments = widget.savedAttachmentData != null
          ? MessageAttachments(
              message: widget.message,
              savedAttachmentData: widget.savedAttachmentData,
              showTail: showTail,
              showHandle: widget.showHandle,
              controllers: widget.currentPlayingVideo,
              changeCurrentPlayingVideo: widget.changeCurrentPlayingVideo,
              allAttachments: widget.allAttachments,
            )
          : Container();

      if (widget.fromSelf) {
        widgetStack.add(SentMessage(
          offset: widget.offset,
          timeStamp: _buildTimeStamp(context),
          message: widget.message,
          chat: widget.chat,
          showDeliveredReceipt:
              widget.customContent == null && widget.isFirstSentMessage,
          showTail: showTail,
          limited: widget.customContent == null,
          shouldFadeIn: widget.shouldFadeIn,
          customContent: widget.customContent,
          isFromMe: widget.fromSelf,
          attachments: widgetAttachments,
          showHero: widget.showHero,
        ));
      } else {
        widgetStack.add(ReceivedMessage(
          offset: widget.offset,
          timeStamp: _buildTimeStamp(context),
          showTail: showTail,
          olderMessage: widget.olderMessage,
          message: widget.message,
          showHandle: widget.showHandle,
          customContent: widget.customContent,
          isFromMe: widget.fromSelf,
          attachments: widgetAttachments,
        ));
      }

      for (Attachment sticker in stickers) {
        widgetStack.add(StickerWidget(attachment: sticker));
      }

      widgetStack.add(Text("")); // Workaround for Flutter bug

      return Stack(
          alignment: widget.fromSelf
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          children: widgetStack);
    }
  }
}
