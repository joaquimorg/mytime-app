package dk.cachet.notifications;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.content.Intent;
import android.os.Build;
import android.os.Build.VERSION_CODES;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import androidx.annotation.RequiresApi;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.concurrent.TimeUnit;

/**
 * Notification listening service. Intercepts notifications if permission is given to do so.
 */
@SuppressLint("OverrideAbstract")
@RequiresApi(api = VERSION_CODES.JELLY_BEAN_MR2)
public class NotificationListener extends NotificationListenerService {

  public static String NOTIFICATION_INTENT = "notification_event";
  public static String NOTIFICATION_PACKAGE_NAME = "notification_package_name";
  public static String NOTIFICATION_MESSAGE = "notification_message";
  public static String NOTIFICATION_TITLE = "notification_title";
  public static String NOTIFICATION_SUBTEXT = "notification_subtext";
  public static String NOTIFICATION_TICKER = "notification_ticker";

  private final HashMap<String, Long> notificationBurstPrevention = new HashMap<>();
  private final HashMap<String, Long> notificationOldRepeatPrevention = new HashMap<>();

  @RequiresApi(api = VERSION_CODES.KITKAT)
  @Override
  public void onNotificationPosted(StatusBarNotification sbn) {
    // Retrieve package name to set as title.
    String packageName = sbn.getPackageName();
    Notification notification = sbn.getNotification();

    if (getApplicationContext().getPackageName().equals(packageName)) {
      return;
    }

    Long notificationOldRepeatPreventionValue = notificationOldRepeatPrevention.get(packageName);
    if (notificationOldRepeatPreventionValue != null
        && notification.when <= notificationOldRepeatPreventionValue
    )
    {
      // NOT processing notification, already sent newer notifications from this source.
      return;
    }

    // Ignore too frequent notifications, according to user preference
    long curTime = System.nanoTime();
    Long notificationBurstPreventionValue = notificationBurstPrevention.get(packageName);
    if (notificationBurstPreventionValue != null) {
      long diff = curTime - notificationBurstPreventionValue;
      if (diff < TimeUnit.SECONDS.toNanos(5)) {
        //LOG.info("Ignoring frequent notification, last one was " + TimeUnit.NANOSECONDS.toMillis(diff) + "ms ago");
        return;
      }
    }

    String title = "";
    String text = "";
    String subText = "";
    String tickerText = "";

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
      // Retrieve extra object from notification to extract payload.
      Bundle extras = notification.extras;

      CharSequence notificationTitle = extras.getCharSequence(Notification.EXTRA_TITLE);
      if (notificationTitle != null) {
        title = notificationTitle.toString();
      }
      CharSequence notificationText = extras.getCharSequence(Notification.EXTRA_TEXT);
      if (notificationText != null) {
          text = notificationText.toString();
      }
      CharSequence notificationSubText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT);
      if (notificationSubText != null) {
         subText = notificationSubText.toString();
      }
    }

    CharSequence notificationTickerText = notification.tickerText;
    if (notificationTickerText != null) {
        tickerText = notificationTickerText.toString();
    }

    notificationBurstPrevention.put(packageName, curTime);
    if(0 != notification.when) {
      notificationOldRepeatPrevention.put(packageName, notification.when);
    }

    // Pass data from one activity to another.
    Intent intent = new Intent(NOTIFICATION_INTENT);
    
    intent.putExtra(NOTIFICATION_PACKAGE_NAME, packageName);
    intent.putExtra(NOTIFICATION_TITLE, title);
    intent.putExtra(NOTIFICATION_MESSAGE, text);
    intent.putExtra(NOTIFICATION_SUBTEXT, subText);
    intent.putExtra(NOTIFICATION_TICKER, tickerText);
    sendBroadcast(intent);
  }
}
