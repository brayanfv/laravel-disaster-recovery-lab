<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Storage;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Schedule::call(function (): void {
    Storage::disk('local')->append(
        'scheduler-dr-test.log',
        now()->format('Y-m-d H:i:s').' DR_TEST_SCHEDULER_001',
    );
})->everyMinute()->description('Append the scheduler disaster recovery marker');
