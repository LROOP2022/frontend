<script setup lang="ts">
import { computed, ref } from 'vue'
import axios from 'axios'
import {
  Button,
  FileUpload,
  InputNumber,
  ProgressSpinner,
  type FileUploadSelectEvent,
} from 'openvue'

type Prediction = { index: string | number | null; probability: number }
type CsvResponse = { predictions: Prediction[] }
type Contribution = { feature: string; value: number; reference: number; delta: number }
type Explanation = {
  method: string
  candidate_count: number
  total_features: number
  exact_match_adjustment: number
  contributions: Contribution[]
}
type IdDetails = Prediction & {
  features: Record<string, number>
  word_count: string
  explanation: Explanation
}
const API =
  import.meta.env.VITE_API_BASE_URL || 'https://api.team-backend.hack.week-infra.ru/api/v1/predict'
const fields = [...Array.from({ length: 1367 }, (_, i) => `feature_${i}`), 'word_count']
const formatter = new Intl.NumberFormat('ru-RU', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
})
const percent = (n: number) => `${formatter.format(n * 100)} %`
const fileSize = (n: number) =>
  n < 1048576 ? `${Math.ceil(n / 1024)} КБ` : `${(n / 1048576).toFixed(1)} МБ`

const objectId = ref<number | undefined>()
const loading = ref(false)
const error = ref('')
const attempted = ref(false)
const predictions = ref<Prediction[]>([])
const selected = ref(0)
const uploadedFile = ref<File | null>(null)
const featureValues = ref<Record<string, string>>({})
const sampleProfiles = ref<{ row: number; values: Record<string, string> }[]>([])
const featureLoading = ref(false)
const featureNotice = ref('')
const explanation = ref<Explanation | null>(null)
const explanationLoading = ref(false)
const search = ref('')
const showAll = ref(false)
let previewRequest = 0

const current = computed(() => predictions.value[selected.value] ?? null)
const currentLabel = computed(() => current.value?.index ?? `Строка ${selected.value + 1}`)
const filteredFields = computed(() =>
  fields.filter((name) => name.includes(search.value.trim().toLowerCase())),
)
const visibleFields = computed(() =>
  showAll.value ? filteredFields.value : filteredFields.value.slice(0, 32),
)
const summary = computed(() => {
  if (predictions.value.length < 2) return null
  let min = Infinity
  let max = -Infinity
  let total = 0
  for (const item of predictions.value) {
    min = Math.min(min, item.probability)
    max = Math.max(max, item.probability)
    total += item.probability
  }
  return {
    min,
    max,
    avg: total / predictions.value.length,
  }
})
const histogram = computed(() => {
  if (!summary.value) return []
  const bins = Array(8).fill(0) as number[]
  const span = summary.value.max - summary.value.min
  for (const item of predictions.value) {
    const bin = span
      ? Math.min(7, Math.floor(((item.probability - summary.value.min) / span) * 8))
      : 3
    bins[bin] = (bins[bin] ?? 0) + 1
  }
  const maximum = Math.max(...bins)
  return bins.map((count) => ({ count, height: `${Math.max(3, (count / maximum) * 100)}%` }))
})
const closest = computed(() => {
  if (!current.value || !Object.keys(featureValues.value).length || !sampleProfiles.value.length)
    return []
  const peers = sampleProfiles.value.filter((item) => item.row !== selected.value)
  const columns = fields.filter((name) => name.startsWith('feature_'))
  const scales = columns.map((name) => {
    const values = [featureValues.value[name], ...peers.map((peer) => peer.values[name])]
      .map(Number)
      .filter(Number.isFinite)
    return Math.max(1e-9, Math.max(...values) - Math.min(...values))
  })
  return peers
    .map((peer) => {
      let sum = 0
      let used = 0
      columns.forEach((name, i) => {
        const a = Number(featureValues.value[name])
        const b = Number(peer.values[name])
        if (!Number.isFinite(a) || !Number.isFinite(b)) return
        const difference = (a - b) / (scales[i] ?? 1)
        sum += difference * difference
        used++
      })
      return {
        index: predictions.value[peer.row]?.index ?? null,
        probability: predictions.value[peer.row]?.probability ?? 0,
        row: peer.row,
        distance: Math.sqrt(sum / Math.max(1, used)),
      }
    })
    .sort((a, b) => a.distance - b.distance)
    .slice(0, 3)
})
const maxContribution = computed(() =>
  Math.max(
    0.000001,
    ...(explanation.value?.contributions ?? []).map((item) => Math.abs(item.delta)),
  ),
)
const point = (n: number) => `${n >= 0 ? '+' : '−'}${formatter.format(Math.abs(n * 100))} п.п.`

function errorText(e: unknown): string {
  if (axios.isAxiosError(e)) {
    if (e.response?.status === 404) return 'ID не найден в датасете'
    if (e.response?.status === 413) return 'Файл слишком большой'
    if (e.response?.status === 422) return 'Проверьте формат данных'
    if (e.response?.status === 503) return 'Сервис поиска временно недоступен'
  }
  return 'Не удалось получить прогноз. Попробуйте ещё раз.'
}

async function predictById() {
  if (objectId.value == null || loading.value) return
  ++previewRequest
  attempted.value = true
  loading.value = true
  error.value = ''
  predictions.value = []
  selected.value = 0
  uploadedFile.value = null
  sampleProfiles.value = []
  featureValues.value = {}
  explanation.value = null
  featureNotice.value = 'По ID API возвращает оценку, но не исходные значения признаков.'
  try {
    const response = await axios.post<Prediction>(`${API}/by-id`, { index: String(objectId.value) })
    predictions.value = [response.data]
    const requestedId = String(objectId.value)
    explanationLoading.value = true
    void axios
      .post<IdDetails>(`${API}/by-id/details`, { index: requestedId })
      .then(({ data }) => {
        if (String(objectId.value) !== requestedId || uploadedFile.value) return
        featureValues.value = Object.fromEntries(
          Object.entries(data.features).map(([name, value]) => [name, String(value)]),
        )
        featureValues.value.word_count = data.word_count
        explanation.value = data.explanation
        featureNotice.value = 'Значения восстановлены из TEST.csv.'
      })
      .catch(() => {
        featureNotice.value = 'Признаки по ID пока не загружены на сервер.'
      })
      .finally(() => {
        explanationLoading.value = false
      })
  } catch (e) {
    error.value = errorText(e)
  } finally {
    loading.value = false
  }
}

// Stream only the selected row, so even a large CSV is not duplicated in memory.
async function readCsvRow(file: File, target: number): Promise<Record<string, string>> {
  const reader = file.stream().getReader()
  const decoder = new TextDecoder('utf-8')
  let header: string[] | null = null
  let values: string[] = []
  let field = ''
  let quoted = false
  let afterQuote = false
  let skipLf = false
  let rowNumber = 0
  const finish = (): Record<string, string> | null => {
    values.push(field)
    field = ''
    const row = values
    values = []
    if (!header) {
      header = row.map((name) => name.replace(/^\uFEFF/, ''))
      return null
    }
    if (rowNumber++ !== target) return null
    return Object.fromEntries(header.map((name, i) => [name, row[i] ?? '']))
  }
  try {
    while (true) {
      const { value, done } = await reader.read()
      const chunk = done ? decoder.decode() : decoder.decode(value, { stream: true })
      for (const ch of chunk) {
        if (skipLf) {
          skipLf = false
          if (ch === '\n') continue
        }
        if (quoted) {
          if (ch === '"') {
            quoted = false
            afterQuote = true
          } else field += ch
        } else if (afterQuote) {
          if (ch === '"') {
            field += '"'
            quoted = true
            afterQuote = false
          } else if (ch === ',') {
            values.push(field)
            field = ''
            afterQuote = false
          } else if (ch === '\n' || ch === '\r') {
            afterQuote = false
            const row = finish()
            if (row) return row
            skipLf = ch === '\r'
          }
        } else if (ch === '"' && field === '') quoted = true
        else if (ch === ',') {
          values.push(field)
          field = ''
        } else if (ch === '\n' || ch === '\r') {
          const row = finish()
          if (row) return row
          skipLf = ch === '\r'
        } else field += ch
      }
      if (done) break
    }
    if (field || values.length) {
      const row = finish()
      if (row) return row
    }
    throw new Error('Row not found')
  } finally {
    await reader.cancel().catch(() => undefined)
  }
}

async function selectPrediction(index: number) {
  selected.value = index
  featureValues.value = {}
  explanation.value = null
  featureNotice.value = ''
  if (!uploadedFile.value) return
  const request = ++previewRequest
  featureLoading.value = true
  try {
    const values = await readCsvRow(uploadedFile.value, index)
    if (request === previewRequest) {
      featureValues.value = values
      const record = Object.fromEntries(
        Object.entries(values).map(([name, value]) => [
          name,
          name.startsWith('feature_') ? Number(value) : value,
        ]),
      )
      explanationLoading.value = true
      try {
        const response = await axios.post<Explanation>(`${API}/explain`, { record })
        if (request === previewRequest) explanation.value = response.data
      } catch {
        if (request === previewRequest)
          featureNotice.value = 'График влияния признаков сейчас недоступен.'
      } finally {
        if (request === previewRequest) explanationLoading.value = false
      }
    }
  } catch {
    if (request === previewRequest)
      featureNotice.value = 'Не удалось показать значения этой строки CSV.'
  } finally {
    if (request === previewRequest) featureLoading.value = false
  }
}

async function uploadCsv(event: FileUploadSelectEvent) {
  const file = event.files?.[0]
  if (!file || loading.value) return
  ++previewRequest
  attempted.value = true
  loading.value = true
  error.value = ''
  predictions.value = []
  selected.value = 0
  uploadedFile.value = file
  sampleProfiles.value = []
  featureValues.value = {}
  explanation.value = null
  featureNotice.value = ''
  const body = new FormData()
  body.append('file', file)
  try {
    const response = await axios.post<CsvResponse>(`${API}/csv`, body)
    if (!response.data.predictions.length) throw new Error('Empty predictions')
    predictions.value = response.data.predictions
    void selectPrediction(0)
    void (async () => {
      const sample: { row: number; values: Record<string, string> }[] = []
      for (let row = 0; row < Math.min(32, response.data.predictions.length); row++) {
        try {
          sample.push({ row, values: await readCsvRow(file, row) })
        } catch {
          break
        }
      }
      if (uploadedFile.value === file) sampleProfiles.value = sample
    })()
  } catch (e) {
    error.value = errorText(e)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="site">
    <div class="glow glow-a"></div>
    <div class="glow glow-b"></div>
    <header class="topbar wrap">
      <div class="brand"><span class="brand-icon">R</span><span>RISK ATLAS</span></div>
      <span class="top-note"><i></i> Аналитическая платформа</span>
    </header>
    <main class="wrap">
      <section class="hero">
        <div>
          <div class="eyebrow"><b></b> ОЦЕНКА ФИНАНСОВОГО РИСКА</div>
          <h1>Ясный взгляд<br /><em>на каждый риск.</em></h1>
          <p>
            Прогноз вероятности банкротства физического лица на основе данных модели. Один ID или
            целый CSV — результат в одном месте.
          </p>
          <div class="chips">
            <span>1367 числовых признаков</span><span>Пакетный анализ CSV</span
            ><span>Оценка 0–100 %</span>
          </div>
        </div>
        <div class="hero-art" aria-hidden="true">
          <div class="art-grid"></div>
          <div class="orbit orbit-a"></div>
          <div class="orbit orbit-b"></div>
          <div class="art-core">R<small>MODEL / 01</small></div>
          <div class="art-tag tag-one">● &nbsp; DATA IN</div>
          <div class="art-tag tag-two">INSIGHT OUT &nbsp; ↗</div>
        </div>
      </section>
      <section class="section">
        <div class="section-head">
          <div>
            <small>01 / ЗАПРОС</small>
            <h2>Рассчитать вероятность</h2>
          </div>
          <p>Выберите способ передачи данных.</p>
        </div>
        <div class="two-col">
          <article class="input-card">
            <div class="input-icon">#</div>
            <small>01 / ПО ОБЪЕКТУ</small>
            <h3>По ID объекта</h3>
            <p>Для объекта, который уже есть в тестовом датасете.</p>
            <label for="object-id">Идентификатор</label>
            <div class="id-controls">
              <InputNumber
                input-id="object-id"
                v-model="objectId"
                allow-empty
                :use-grouping="false"
                fluid
                placeholder="Например, 194357"
                @keyup.enter="predictById"
              /><Button
                label="Рассчитать"
                :disabled="loading || objectId == null"
                @click="predictById"
              />
            </div>
          </article>
          <article class="input-card dark-card">
            <div class="input-icon">↥</div>
            <small>02 / ПАКЕТНЫЙ АНАЛИЗ</small>
            <h3>Загрузить CSV</h3>
            <p>Оцените несколько объектов и сравните результаты между собой.</p>
            <div class="upload-controls">
              <FileUpload
                :disabled="loading"
                mode="basic"
                name="file[]"
                accept=".csv"
                custom-upload
                choose-label="Выбрать CSV-файл"
                choose-icon="oi oi-upload"
                :choose-button-props="{ outlined: true }"
                @select="uploadCsv"
              /><span>{{
                uploadedFile ? fileSize(uploadedFile.size) : 'CSV с feature_0…feature_1366'
              }}</span>
            </div>
          </article>
        </div>
      </section>
      <section v-if="attempted" class="section">
        <div class="section-head">
          <div>
            <small>02 / РЕЗУЛЬТАТ</small>
            <h2>Результат анализа</h2>
          </div>
          <p v-if="uploadedFile && predictions.length">
            Объектов в файле: {{ predictions.length }}
          </p>
        </div>
        <div v-if="loading" class="state">
          <ProgressSpinner style="width: 42px; height: 42px" />
          <div>
            <strong>Анализируем данные</strong><span>Это может занять несколько секунд.</span>
          </div>
        </div>
        <div v-else-if="error" class="state error-state">
          <b>!</b>
          <div>
            <strong>{{ error }}</strong
            ><span>Проверьте данные и повторите запрос.</span>
          </div>
        </div>
        <template v-else-if="current"
          ><div v-if="predictions.length > 1" class="selection">
            <label for="selected-object">Выберите объект:</label
            ><select
              id="selected-object"
              :value="selected"
              @change="selectPrediction(Number(($event.target as HTMLSelectElement).value))"
            >
              <option v-for="(item, i) in predictions" :key="i" :value="i">
                {{ item.index ?? `Строка ${i + 1}` }}
              </option>
            </select>
          </div>
          <div class="two-col result-layout">
            <article class="score-card">
              <div class="score-top">
                <small>ВЕРОЯТНОСТЬ БАНКРОТСТВА</small><span>ID {{ currentLabel }}</span>
              </div>
              <div class="score-body">
                <div
                  class="score-ring"
                  :style="{
                    '--angle': `${Math.min(100, Math.max(0, current.probability * 100)) * 3.6}deg`,
                  }"
                >
                  <div>
                    <strong>{{ percent(current.probability) }}</strong
                    ><small>оценка модели</small>
                  </div>
                </div>
                <div class="score-copy">
                  <span>Прогноз для объекта</span>
                  <h3>{{ percent(current.probability) }}</h3>
                  <p>
                    Число показывает оценку модели от 0 до 100 %. Для принятия решений нужна
                    отдельная проверка порога.
                  </p>
                </div>
              </div>
              <div class="scale"><span>0 %</span><i></i><span>100 %</span></div>
            </article>
            <article class="insight-card">
              <div class="input-icon">↗</div>
              <small>КАК ЧИТАТЬ ОЦЕНКУ</small>
              <h3>Один показатель.<br />Больше контекста.</h3>
              <p>
                Чем выше значение, тем выше оценённый моделью риск. Показанный процент не означает,
                что вероятность откалибрована.
              </p>
              <div>
                <span>Источник</span
                ><strong>{{ uploadedFile ? 'Загруженный CSV' : 'Поиск по ID' }}</strong>
              </div>
            </article>
          </div>
          <div v-if="summary" class="two-col cohort-layout">
            <article class="cohort-card">
              <small>РАСПРЕДЕЛЕНИЕ В ФАЙЛЕ</small>
              <h3>Оценки в вашей выборке</h3>
              <div class="histogram" aria-label="Распределение оценок в CSV">
                <i
                  v-for="(bar, i) in histogram"
                  :key="i"
                  :style="{ height: bar.height }"
                  :title="`${bar.count} объектов`"
                ></i>
              </div>
              <div class="hist-labels">
                <span>{{ percent(summary.min) }}</span
                ><span>{{ percent(summary.max) }}</span>
              </div>
              <div class="cohort-stats">
                <div>
                  <small>МИНИМУМ</small><b>{{ percent(summary.min) }}</b>
                </div>
                <div>
                  <small>СРЕДНЕЕ</small><b>{{ percent(summary.avg) }}</b>
                </div>
                <div>
                  <small>МАКСИМУМ</small><b>{{ percent(summary.max) }}</b>
                </div>
              </div>
            </article>
            <article class="cohort-card">
              <small>СХОДСТВО ПРОФИЛЕЙ</small>
              <h3>Похожие объекты</h3>
              <p>
                Сравниваем 1367 числовых признаков среди первых 32 строк этого CSV. Это сходство
                профилей, а не подтверждённый исход банкротства.
              </p>
              <button
                v-for="item in closest"
                :key="item.row"
                type="button"
                class="nearby"
                @click="selectPrediction(item.row)"
              >
                <span
                  ><b>{{ String(item.row + 1).padStart(2, '0') }}</b> ID
                  {{ item.index ?? `строка ${item.row + 1}` }}</span
                ><strong>{{ percent(item.probability) }}</strong>
              </button>
            </article>
          </div>
        </template>
      </section>
      <section v-if="current && (explanation || explanationLoading)" class="section impact-section">
        <div class="section-head">
          <div>
            <small>03 / ОБЪЯСНЕНИЕ</small>
            <h2>Что меняет оценку модели</h2>
          </div>
          <p>Анализ признаков выбранного объекта</p>
        </div>
        <div v-if="explanationLoading && !explanation" class="state">
          <ProgressSpinner style="width: 34px; height: 34px" />
          <div>
            <strong>Считаем влияние признаков</strong
            ><span>Повторно запускаем модель для сравнения.</span>
          </div>
        </div>
        <div v-else-if="explanation" class="impact-card">
          <div class="impact-head">
            <div>
              <span class="impact-pill">АНАЛИЗ ЧУВСТВИТЕЛЬНОСТИ</span>
              <h3>Главные факторы в прогнозе</h3>
            </div>
            <div class="impact-legend">
              <span><i class="risk-dot"></i> повышает оценку</span
              ><span><i class="safe-dot"></i> снижает оценку</span>
            </div>
          </div>
          <div class="impact-list">
            <div v-for="item in explanation.contributions" :key="item.feature" class="impact-row">
              <div class="impact-label">
                <strong>{{ item.feature }}</strong
                ><span
                  >Значение {{ formatter.format(item.value) }} · медиана
                  {{ formatter.format(item.reference) }}</span
                >
              </div>
              <div class="impact-track">
                <i class="impact-center"></i
                ><b
                  :class="item.delta >= 0 ? 'risk-bar' : 'safe-bar'"
                  :style="{
                    width: `${Math.max(2, (Math.abs(item.delta) / maxContribution) * 48)}%`,
                  }"
                ></b>
              </div>
              <strong class="impact-value" :class="item.delta >= 0 ? 'risk-text' : 'safe-text'">{{
                point(item.delta)
              }}</strong>
            </div>
          </div>
          <p class="impact-note">
            Для каждого признака модель рассчитана повторно после замены его значения на медиану
            обучения. Показана разница оценок в процентных пунктах. Это не SHAP: значения не
            складываются в итоговый процент. Проверены 48 признаков с наибольшей важностью в
            деревьях модели; показаны 16 сильнейших из них.
          </p>
          <p v-if="Math.abs(explanation.exact_match_adjustment) > 0.000001" class="impact-note">
            Поправка за точное совпадение с обучающим профилем:
            {{ point(explanation.exact_match_adjustment) }}. Она не распределена между признаками.
          </p>
        </div>
      </section>
      <section class="section features-section">
        <div class="section-head">
          <div>
            <small>04 / ДАННЫЕ</small>
            <h2>Признаки модели</h2>
          </div>
          <p>1367 числовых полей и word_count</p>
        </div>
        <div class="features-panel">
          <div class="features-head">
            <div>
              <strong>Каталог признаков</strong
              ><span v-if="featureLoading">Загружаем значения выбранной строки…</span
              ><span v-else-if="featureNotice">{{ featureNotice }}</span
              ><span v-else-if="uploadedFile && current">Значения взяты из загруженного CSV.</span
              ><span v-else>Загрузите CSV, чтобы увидеть значения объекта.</span>
            </div>
            <label class="search"
              ><span>⌕</span
              ><input
                v-model="search"
                type="search"
                placeholder="Найти признак"
                aria-label="Найти признак"
                @input="showAll = false"
            /></label>
          </div>
          <div class="feature-grid">
            <div v-for="name in visibleFields" :key="name" class="feature">
              <code>{{ name }}</code
              ><span :title="featureValues[name] || ''">{{ featureValues[name] || '—' }}</span>
            </div>
            <p v-if="!filteredFields.length">Ничего не найдено</p>
          </div>
          <button
            v-if="filteredFields.length > 32"
            type="button"
            class="show-all"
            @click="showAll = !showAll"
          >
            {{ showAll ? 'Свернуть список' : `Показать все ${filteredFields.length} полей` }} ↗
          </button>
        </div>
      </section>
    </main>
    <footer class="footer wrap">
      <span>RISK ATLAS / АНАЛИТИКА БАНКРОТСТВА</span
      ><span>Данные → модель → понятный результат</span>
    </footer>
  </div>
</template>
