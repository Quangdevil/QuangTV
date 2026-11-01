import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('auto_patch', ROOT / 'scripts/patch_android_auto.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
A = '{http://schemas.android.com/apk/res/android}'


class AutoPatchTest(unittest.TestCase):
    def test_patch_preserves_phone_entry_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder)
            main = app / 'src/main'
            main.mkdir(parents=True)
            manifest = main / 'AndroidManifest.xml'
            manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
              <application android:name="${applicationName}">
                <activity android:name=".MainActivity" android:exported="true"/>
              </application></manifest>''')
            (app / 'build.gradle').write_text('plugins {}\n')
            (app / 'proguard-rules.pro').write_text('')
            module.patch(app)
            first = {p.relative_to(app): p.read_bytes() for p in app.rglob('*') if p.is_file()}
            module.patch(app)
            self.assertEqual(first, {p.relative_to(app): p.read_bytes() for p in app.rglob('*') if p.is_file()})
            application = ET.parse(manifest).getroot().find('application')
            self.assertEqual('${applicationName}', application.get(A + 'name'))
            self.assertEqual('.MainActivity', application.find('activity').get(A + 'name'))
            self.assertEqual(2, len(application.findall('activity')))
            service = application.find('service')
            self.assertEqual('true', service.get(A + 'exported'))
            self.assertEqual('com.google.android.gms.car.category.CATEGORY_PROJECTION',
                             service.find('intent-filter/category').get(A + 'name'))
            self.assertIn('com.google.android.gms.car.category.CATEGORY_PROJECTION_OEM',
                          [c.get(A + 'name') for c in service.findall('intent-filter/category')])
            self.assertFalse(list(application.iter('uses-feature')))
            self.assertTrue((app / 'src/main/java/app/tvviewer/player/QuangAutoActivity.java').is_file())


if __name__ == '__main__':
    unittest.main()
