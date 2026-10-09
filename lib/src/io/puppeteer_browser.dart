import 'dart:async';
import 'dart:io';

import 'package:flighthouse/src/io/browser.dart';
import 'package:flighthouse/src/result/failure.dart';
import 'package:flighthouse/src/result/result.dart';
import 'package:puppeteer/puppeteer.dart' as puppeteer;

Future<Result<BrowserSession, IoFailure>> launchPuppeteerBrowser({
  required String cachePath,
  required BrowserViewport viewport,
  required Duration acquireTimeout,
  required Duration launchTimeout,
  Map<String, String>? environment,
}) {
  final sandboxDisabled = chromeSandboxDisabled(
    environment ?? Platform.environment,
  );
  return launchBrowser(
    cachePath: cachePath,
    viewport: viewport,
    acquireTimeout: acquireTimeout,
    launchTimeout: launchTimeout,
    acquire: _acquirePuppeteerBrowser,
    launch: (installation, viewport, timeout) => _launchPuppeteerBrowser(
      installation,
      viewport,
      timeout,
      sandboxDisabled: sandboxDisabled,
    ),
  );
}

Future<BrowserInstallation> _acquirePuppeteerBrowser(String cachePath) async {
  final downloaded = await puppeteer.downloadChrome(cachePath: cachePath);
  return BrowserInstallation(
    cachePath: cachePath,
    executablePath: downloaded.executablePath,
    version: downloaded.version,
  );
}

Future<BrowserBindings> _launchPuppeteerBrowser(
  BrowserInstallation installation,
  BrowserViewport viewport,
  Duration timeout, {
  required bool sandboxDisabled,
}) async {
  puppeteer.Browser? browser;
  try {
    browser = await puppeteer.puppeteer.launch(
      executablePath: installation.executablePath,
      noSandboxFlag: sandboxDisabled,
      timeout: timeout,
      defaultViewport: puppeteer.DeviceViewport(
        width: viewport.width,
        height: viewport.height,
        deviceScaleFactor: viewport.deviceScaleFactor,
      ),
    );
    final pages = await browser.pages;
    final page = pages.isEmpty ? await browser.newPage() : pages.first;
    final crashed = Completer<void>();
    final crashes = page.onPageCrashed.listen((_) {
      if (!crashed.isCompleted) crashed.complete();
    });
    await page.evaluateOnNewDocument(_firstFrameListener);
    final endpoint = Uri.parse(browser.wsEndpoint);
    final info = BrowserInfo(
      installation: installation,
      browserVersion: await browser.version,
      debuggingPort: endpoint.port,
    );
    return BrowserBindings(
      info: info,
      navigate: (url, navigationTimeout) async {
        await page.goto(
          url.toString(),
          timeout: navigationTimeout,
          wait: puppeteer.Until.domContentLoaded,
        );
      },
      waitForFirstFrame: (firstFrameTimeout) async {
        await page.waitForFunction(
          '() => globalThis.__flighthouseFirstFrame === true',
          timeout: firstFrameTimeout,
        );
      },
      currentUrl: () => page.url ?? '',
      waitForSelector: (selector, selectorTimeout) async {
        final handle = await page.waitForSelector(
          selector,
          visible: true,
          timeout: selectorTimeout,
        );
        await handle?.dispose();
      },
      click: page.click,
      focus: page.click,
      waitForFocus: (selector, focusTimeout) async {
        await page.waitForFunction(
          'selector => document.activeElement === '
          'document.querySelector(selector)',
          args: [selector],
          timeout: focusTimeout,
        );
      },
      settleInput: () => page.evaluate<void>(_settleInput),
      replaceInput: (selector, value) async {
        await page.evaluate<void>(_selectInput, args: [selector]);
        await page.keyboard.sendCharacter(value);
      },
      readInput: (selector) =>
          page.evaluate<String?>(_readInput, args: [selector]),
      evaluate: (script, arguments) =>
          page.evaluate<Object?>(script, args: arguments),
      close: () async {
        await crashes.cancel();
        await _closeBrowser(browser!);
      },
      rendererCrashed: () => crashed.future,
    );
  } on Exception catch (_) {
    await _disposeFailedLaunch(browser);
    rethrow;
  }
}

Future<void> _disposeFailedLaunch(puppeteer.Browser? browser) async {
  if (browser == null) return;
  try {
    await browser.close();
  } on Exception catch (_) {
    browser.process?.kill();
  }
}

Future<void> _closeBrowser(puppeteer.Browser browser) async {
  try {
    await browser.close();
  } on Exception catch (_) {
    browser.process?.kill();
    rethrow;
  }
}

const _firstFrameListener = '''
() => {
  globalThis.__flighthouseFirstFrame = false;
  globalThis.addEventListener('flutter-first-frame', () => {
    globalThis.__flighthouseFirstFrame = true;
  }, {once: true});
}
''';

const _settleInput = '''
() => new Promise((resolve) => {
  requestAnimationFrame(() => requestAnimationFrame(resolve));
})
''';

const _selectInput = '''
selector => {
  const element = document.querySelector(selector);
  if (element !== null && typeof element.select === 'function') {
    element.select();
  }
}
''';

const _readInput = '''
selector => {
  const element = document.querySelector(selector);
  return element === null || typeof element.value !== 'string'
    ? null
    : element.value;
}
''';
