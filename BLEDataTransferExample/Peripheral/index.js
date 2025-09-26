const LOCAL_NAME             = "PIYO_BLE_SERVER";
const SERVICE_UUID           = "98988A2A-64BE-45E1-8069-3F37EAF01611".replace(/-/g, '');
const CHARACTERISTIC_UUID    = "98988A2A-64BE-45E1-8069-3F37EAF01612".replace(/-/g, '');

const bleno = require('@abandonware/bleno');
var counter = 0;
var characteristicUpdateValueCallback = null;

const characteristic = new bleno.Characteristic({
    uuid: CHARACTERISTIC_UUID,
    properties: ['read', 'write', 'notify'],
    onReadRequest: (offset, callback) => {
        console.log(`[BLE] read`);
        callback(bleno.Characteristic.RESULT_SUCCESS, Buffer.from(new Int8Array([counter])));
    },
    onWriteRequest: (data, offset, withoutResponse, callback) => {
        console.log(`[BLE] write: ${data}`);
        callback(bleno.Characteristic.RESULT_SUCCESS);
    },
    onSubscribe: (maxValueSize, updateValueCallback) => {
        console.log(`[BLE] subscribe: ${maxValueSize}`);
        characteristicUpdateValueCallback = updateValueCallback;
    },
    onUnsubscribe: () => {
        console.log(`[BLE] unsubscribe`);
        characteristicUpdateValueCallback = null;
    },
    onNotify: () => {
        console.log(`[BLE] notify`);
    },
});

const service = new bleno.PrimaryService({ 
    uuid: SERVICE_UUID,
    characteristics: [characteristic],
});

bleno.on('stateChange', (state) => {
    console.log(`[BLE] stateChange: ${state}`);
    if (state === 'poweredOn') {
        startAdvertising();
    } else {
        bleno.stopAdvertising();
    }
});

bleno.on('advertisingStart', (error) => {
    console.log(`[BLE] advertisingStart`);
    bleno.setServices([service])
    if (error) {
        console.log(`[BLE] error: ${error}`);
    }
});

bleno.on('accept', (clientAddress) => {
    console.log(`[BLE] accept: ${clientAddress}`);
});

bleno.on('disconnect', (clientAddress) => {
    console.log(`[BLE] disconnect: ${clientAddress}`);
});

function startAdvertising() {
    bleno.startAdvertising(LOCAL_NAME, [service.uuid]);
}

setInterval(()=>{
    counter++;
    if (characteristicUpdateValueCallback) {
        characteristicUpdateValueCallback(Buffer.from(new Int8Array([counter])));
    }
}, 1000);
