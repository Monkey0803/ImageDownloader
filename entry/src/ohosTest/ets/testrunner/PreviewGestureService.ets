import { abilityDelegatorRegistry, Driver, PointerMatrix, DisplayRotation } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';

class GestureCommand {
  id: string = '';
  operation: string = '';
  x: number = 0;
  y: number = 0;
  from: number = 80;
  to: number = 300;
  dx: number = 0;
  dy: number = 0;
  rotation: number = 0;
  autoRotate: boolean = false;
  speed: number = 1200;
}

class RotationSnapshot {
  rotation: DisplayRotation = DisplayRotation.ROTATION_0;
  autoRotate: boolean = false;
}

class GestureResult {
  id: string = '';
  success: boolean = false;
  detail: string = '';
  captures: string[] = [];
  elapsed: number[] = [];
}

// Opt-in device acceptance helper. It never launches an ability or resets the app.
// Start once with aa test, then send commands through the app's cache directory.
export class PreviewGestureService {
  private running: boolean = true;

  stop(): void { this.running = false; }

  async run(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const cache = delegator.getAppContext().cacheDir;
    const commandPath = `${cache}/preview-gesture-command.json`;
    const resultPath = `${cache}/preview-gesture-result.json`;
    const rotationPath = `${cache}/preview-gesture-rotation.json`;
    await delegator.print(`PreviewGestureRunner ready: ${commandPath}\n`);
    while (this.running) {
      if (fs.accessSync(commandPath)) {
        const result = new GestureResult();
        try {
          const command: GestureCommand = JSON.parse(fs.readTextSync(commandPath));
          fs.unlinkSync(commandPath);
          result.id = command.id;
          const driver = Driver.create();
          if (driver === null || driver === undefined) {
            throw new Error('UiTest Driver unavailable after foreground launch');
          }
          if (command.operation === 'pinch') {
            const size = await driver.getDisplaySize();
            const steps = 20;
            const pointers = PointerMatrix.create(2, steps);
            if (!Number.isFinite(command.x) || !Number.isFinite(command.y) ||
              !Number.isFinite(command.from) || !Number.isFinite(command.to) ||
              !Number.isFinite(command.dx) || !Number.isFinite(command.dy) ||
              command.from <= 0 || command.to <= 0) {
              throw new Error('Invalid pinch coordinates');
            }
            for (let step = 0; step < steps; step++) {
              const fraction = step / (steps - 1);
              const radius = command.from + (command.to - command.from) * fraction;
              const x = command.x + command.dx * fraction;
              const y = command.y + command.dy * fraction;
              if (x - radius < 0 || x + radius >= size.x || y < 0 || y >= size.y) {
                throw new Error('Pinch trace lies outside display');
              }
              pointers.setPoint(0, step, { x: Math.round(x - radius), y: Math.round(y) });
              pointers.setPoint(1, step, { x: Math.round(x + radius), y: Math.round(y) });
            }
            result.success = await driver.injectMultiPointerAction(pointers, 600);
          } else if (command.operation === 'swipe-capture') {
            const size = await driver.getDisplaySize();
            if (!/^[a-zA-Z0-9_-]{1,48}$/.test(command.id) ||
              !Number.isFinite(command.x) || !Number.isFinite(command.y) ||
              !Number.isFinite(command.dx) || !Number.isFinite(command.dy) ||
              !Number.isFinite(command.speed) || command.speed < 200 || command.speed > 15000 ||
              command.x < 0 || command.x >= size.x || command.x + command.dx < 0 || command.x + command.dx >= size.x ||
              command.y < 0 || command.y >= size.y || command.y + command.dy < 0 || command.y + command.dy >= size.y) {
              throw new Error('Invalid swipe capture command');
            }
            await driver.swipe(command.x, command.y, command.x + command.dx, command.y + command.dy, command.speed);
            const ended: number = Date.now();
            const delays: number[] = [0, 100, 250, 500, 1000];
            for (let index: number = 0; index < delays.length; index++) {
              const remaining: number = delays[index] - (Date.now() - ended);
              if (remaining > 0) { await driver.delayMs(remaining); }
              const path: string = cache + '/preview-reading-motion-' + command.id + '-' + index.toString() + '.png';
              if (!await driver.screenCap(path)) { throw new Error('Motion screenshot failed'); }
              result.captures.push(path);
              result.elapsed.push(Date.now() - ended);
            }
            result.success = true;
          } else if (command.operation === 'rotate') {
            if (!Number.isInteger(command.rotation) || command.rotation < 0 || command.rotation > 3 ||
              typeof command.autoRotate !== 'boolean') {
              throw new Error('Rotation requires 0..3 and recorded original autoRotate');
            }
            if (!fs.accessSync(rotationPath)) {
              const snapshot = new RotationSnapshot();
              snapshot.rotation = await driver.getDisplayRotation();
              snapshot.autoRotate = command.autoRotate;
              this.write(rotationPath, JSON.stringify(snapshot));
            }
            await driver.setDisplayRotationEnabled(true);
            await driver.setDisplayRotation(command.rotation);
            result.success = true;
          } else if (command.operation === 'restore' || command.operation === 'stop') {
            if (fs.accessSync(rotationPath)) {
              const snapshot: RotationSnapshot = JSON.parse(fs.readTextSync(rotationPath));
              await driver.setDisplayRotationEnabled(true);
              await driver.setDisplayRotation(snapshot.rotation);
              await driver.setDisplayRotationEnabled(snapshot.autoRotate);
              fs.unlinkSync(rotationPath);
            }
            if (command.operation === 'stop') { this.running = false; }
            result.success = true;
          } else {
            throw new Error('Unknown gesture operation');
          }
          result.detail = `rotation=${await driver.getDisplayRotation()}`;
        } catch (error) {
          result.detail = `${error}`;
          if (fs.accessSync(commandPath)) { fs.unlinkSync(commandPath); }
        }
        this.write(resultPath, JSON.stringify(result));
      }
      await new Promise<void>((resolve) => { setTimeout(resolve, 250); });
    }
    await delegator.finishTest('Preview gesture service stopped', 0);
  }

  private write(path: string, content: string): void {
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, content); } finally { fs.closeSync(file); }
  }
}
