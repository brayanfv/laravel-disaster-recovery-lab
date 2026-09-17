<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class SchedulerDrTest extends TestCase
{
    public function test_scheduler_appends_the_disaster_recovery_marker_to_private_storage(): void
    {
        config()->set('cache.default', 'file');
        Storage::fake('local');
        $this->travelTo('2026-09-17 16:00:00');

        Artisan::call('schedule:run');

        Storage::disk('local')->assertExists('scheduler-dr-test.log');
        $this->assertSame(
            '2026-09-17 16:00:00 DR_TEST_SCHEDULER_001',
            Storage::disk('local')->get('scheduler-dr-test.log'),
        );
    }
}
