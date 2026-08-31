package com.example.vision_wear

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Routes the app's sockets over WiFi, and holds a multicast lock while we are
 * listening for the camera's discovery beacon.
 *
 * Why this exists: the ESP32-CAM serves its own access point with no internet
 * behind it. When the phone joins a network like that, Android notices the
 * missing internet and keeps mobile data as the *default* network. Every
 * `http.get("http://192.168.4.1/...")` the app makes is then sent out of the
 * cellular interface, where that address does not exist, and fails. The user
 * sees "camera not connecting" while their phone is plainly connected to the
 * camera's WiFi.
 *
 * `bindProcessToNetwork` pins this process's traffic to the WiFi interface so
 * those requests reach the camera. It is deliberately scoped: the app binds
 * while talking to the ESP32 and unbinds otherwise, because while bound the
 * process cannot reach the internet at all.
 *
 * The multicast lock is the second half of the problem. Android's WiFi power
 * saving drops broadcast and multicast frames that are not addressed to the
 * phone, which silently swallows the UDP discovery beacon.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "vision_wear/network"
    private var multicastLock: WifiManager.MulticastLock? = null

    private val connectivityManager: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> result.success(bindToWifi())
                    "unbind" -> result.success(unbind())
                    "status" -> result.success(status())
                    "acquireMulticastLock" -> result.success(acquireMulticastLock())
                    "releaseMulticastLock" -> result.success(releaseMulticastLock())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        unbind()
        super.onDestroy()
    }

    /** Returns true when this process is now pinned to a WiFi network. */
    private fun bindToWifi(): Boolean {
        val wifi = findWifiNetwork() ?: return false
        return try {
            connectivityManager.bindProcessToNetwork(wifi)
        } catch (e: Exception) {
            false
        }
    }

    private fun unbind(): Boolean {
        return try {
            connectivityManager.bindProcessToNetwork(null)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * What the Dart side needs to explain a failure to the user: is WiFi up at
     * all, and is Android treating it as the default route?
     */
    private fun status(): Map<String, Any> {
        val wifi = findWifiNetwork()
        val active = connectivityManager.activeNetwork
        val activeCaps = active?.let { connectivityManager.getNetworkCapabilities(it) }

        return mapOf(
            "hasWifi" to (wifi != null),
            "wifiIsDefault" to (wifi != null && wifi == active),
            "activeIsCellular" to (activeCaps
                ?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true),
            // A WiFi network with no internet is the normal case for the
            // camera's own access point, not an error.
            "wifiHasInternet" to (wifi
                ?.let { connectivityManager.getNetworkCapabilities(it) }
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true)
        )
    }

    private fun findWifiNetwork(): Network? {
        return connectivityManager.allNetworks.firstOrNull { network ->
            connectivityManager.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    }

    private fun acquireMulticastLock(): Boolean {
        if (multicastLock?.isHeld == true) return true
        return try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val lock = wifiManager.createMulticastLock("visionwear-discovery")
            lock.setReferenceCounted(false)
            lock.acquire()
            multicastLock = lock
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun releaseMulticastLock(): Boolean {
        return try {
            multicastLock?.takeIf { it.isHeld }?.release()
            multicastLock = null
            true
        } catch (e: Exception) {
            false
        }
    }
}
