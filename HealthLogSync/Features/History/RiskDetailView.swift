import SwiftUI

struct RiskDetailView: View {
    let risk: RiskItem

    private var info: RiskInfo {
        RiskInfo.info(for: risk.type)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                explanationCard
                dataUsedCard
                recommendationsCard
                doctorVisitCard
            }
            .padding()
        }
        .navigationTitle(risk.localizedName)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Circle()
                    .fill(risk.severityColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 3)
                Text(risk.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                severityBadge
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Уверенность алгоритма")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(risk.confidence * 100))%")
                        .font(.caption.bold())
                }
                ProgressView(value: risk.confidence)
                    .tint(risk.severityColor)
            }

            if risk.severity != "high" {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(
                        "«\(risk.severityLabel)» — уровень потенциального вреда, а не вероятность. Уверенность показывает, насколько алгоритм уверен в обнаружении паттерна."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var severityBadge: some View {
        Text(risk.severityLabel)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(risk.severityColor.opacity(0.15))
            .foregroundStyle(risk.severityColor)
            .clipShape(Capsule())
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Что это означает", systemImage: "questionmark.circle.fill")
                .font(.subheadline.bold())
            Text(info.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Health Data

    private var dataUsedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Данные анализа", systemImage: "chart.bar.doc.horizontal.fill")
                .font(.subheadline.bold())
            ForEach(info.healthDataTypes, id: \.self) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(item)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recommendations

    private var recommendationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Что делать", systemImage: "checklist")
                .font(.subheadline.bold())
            ForEach(Array(info.actions.enumerated()), id: \.offset) { _, action in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(action)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Doctor Visit

    private var doctorVisitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Визит к врачу", systemImage: "stethoscope")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("К какому врачу")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(info.doctorType)
                    .font(.subheadline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Что сказать на приёме")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(info.doctorVisitReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            if !info.testsToOrder.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Попросить назначить")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(info.testsToOrder, id: \.self) { test in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(test)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Risk Info

private struct RiskInfo {
    let explanation: String
    let doctorType: String
    let actions: [String]
    let doctorVisitReason: String
    let testsToOrder: [String]
    let healthDataTypes: [String]

    // swiftlint:disable function_body_length
    static func info(for type: String) -> RiskInfo {
        switch type {
        case "overload_recovery_risk":
            return RiskInfo(
                explanation: "Алгоритм обнаружил признаки хронической усталости, недостаточного сна или неполного восстановления. Причиной могут быть интенсивные тренировки, длительный стресс или систематическое недосыпание. Со временем это повышает риск травм, снижает иммунитет и когнитивные функции.",
                doctorType: "Терапевт, Сомнолог",
                actions: [
                    "Нормализовать режим сна: ложиться и вставать в одно время",
                    "Обеспечить 7–9 часов сна в сутки",
                    "Снизить интенсивность тренировок на 20–30% на 2 недели",
                    "Добавить дни восстановления между нагрузками",
                    "Ограничить кофеин после 14:00",
                ],
                doctorVisitReason: "«Мой трекер фиксирует сниженную вариабельность сердечного ритма и признаки недовосстановления. Хочу исключить патологические причины и получить рекомендации.»",
                testsToOrder: ["Общий анализ крови", "Кортизол (утренний)", "Ферритин", "Витамин D"],
                healthDataTypes: ["Вариабельность сердечного ритма (HRV)", "ЧСС в покое", "Продолжительность и фазы сна", "Активность и тренировки"]
            )
        case "noise_exposure_risk":
            return RiskInfo(
                explanation: "Зафиксировано регулярное воздействие звука выше безопасного порога (85 дБ). Длительное воздействие громкого звука вызывает необратимое повреждение волосковых клеток внутреннего уха и постепенную потерю слуха.",
                doctorType: "ЛОР (оториноларинголог), Аудиолог",
                actions: [
                    "Снизить громкость наушников до 60% от максимума",
                    "Не использовать наушники более 60 минут подряд",
                    "Применять беруши или наушники с ANC в шумных местах",
                    "Делать перерывы в тишине — не менее 10 минут каждый час",
                ],
                doctorVisitReason: "«Apple Health фиксирует регулярное воздействие звука выше безопасного уровня. Хочу пройти проверку слуха и получить рекомендации по профилактике.»",
                testsToOrder: ["Аудиограмма", "Тимпанометрия"],
                healthDataTypes: ["Уровень шума окружающей среды", "Экспозиция звука через наушники"]
            )
        case "obesity_risk":
            return RiskInfo(
                explanation: "Показатели массы тела выходят за пределы нормального диапазона. Ожирение увеличивает риск сердечно-сосудистых заболеваний, диабета 2 типа, апноэ сна и нарушений опорно-двигательного аппарата.",
                doctorType: "Эндокринолог, Диетолог",
                actions: [
                    "Проконсультироваться с диетологом для составления индивидуального плана",
                    "Добавить 30 минут умеренной активности ежедневно",
                    "Вести дневник питания хотя бы 2 недели",
                    "Ограничить ультраобработанные продукты и добавленный сахар",
                ],
                doctorVisitReason: "«Мой ИМТ выходит за пределы нормы. Хочу получить план снижения веса и исключить гормональные или метаболические причины.»",
                testsToOrder: ["ТТГ (щитовидная железа)", "Инсулин натощак", "Глюкоза натощак", "Липидограмма"],
                healthDataTypes: ["Масса тела", "ИМТ", "Состав тела (если доступен)"]
            )
        case "sedentary_lifestyle_risk":
            return RiskInfo(
                explanation: "Зафиксированы длительные периоды без движения. Малоподвижный образ жизни повышает риск сердечно-сосудистых заболеваний и метаболических нарушений — даже при наличии регулярных тренировок.",
                doctorType: "Терапевт, Кардиолог",
                actions: [
                    "Вставать и ходить хотя бы 2 минуты каждый час",
                    "Настроить напоминания о движении (каждые 50–60 минут)",
                    "По возможности использовать стоячее рабочее место",
                    "Добавить 10-минутные прогулки после каждого приёма пищи",
                ],
                doctorVisitReason: "«Трекер показывает более 8–10 часов в сидячем положении ежедневно. Хочу узнать о рисках и получить план профилактики.»",
                testsToOrder: ["ЭКГ", "Липидограмма", "Глюкоза натощак"],
                healthDataTypes: ["Время стояния", "Количество шагов", "Активная энергия", "Продолжительность малоподвижных периодов"]
            )
        case "insufficient_activity_risk":
            return RiskInfo(
                explanation: "Общий уровень ежедневной активности ниже рекомендованного ВОЗ минимума — 150 минут умеренной нагрузки в неделю. Это один из ведущих факторов риска хронических неинфекционных заболеваний.",
                doctorType: "Терапевт, Врач ЛФК",
                actions: [
                    "Поставить цель — 7 000–10 000 шагов в день",
                    "Добавить 150 минут умеренной аэробной активности в неделю",
                    "Начать с коротких прогулок, постепенно увеличивая длительность",
                    "Рассмотреть плавание, велопрогулки или скандинавскую ходьбу",
                ],
                doctorVisitReason: "«Мой уровень физической активности ниже нормы. Хочу получить безопасный план постепенного увеличения нагрузки с учётом состояния здоровья.»",
                testsToOrder: ["Нагрузочный тест (ЭКГ с нагрузкой)", "Общий анализ крови"],
                healthDataTypes: ["Количество шагов", "Минуты активности", "Активная энергия", "Тренировки"]
            )
        case "cardiometabolic_risk":
            return RiskInfo(
                explanation: "Совокупность показателей — пульс, вариабельность ритма, активность — указывает на ухудшение кардиометаболического профиля. Это предиктор сердечно-сосудистых заболеваний и метаболических нарушений при отсутствии коррекции.",
                doctorType: "Кардиолог, Терапевт",
                actions: [
                    "Измерять артериальное давление 2 раза в день в течение 7 дней",
                    "Добавить аэробные нагрузки средней интенсивности 3–5 раз в неделю",
                    "Оптимизировать питание: больше овощей, меньше соли и насыщенных жиров",
                    "Практиковать управление стрессом: дыхательные упражнения, медитация",
                ],
                doctorVisitReason: "«Носимое устройство фиксирует нарушения кардиометаболических показателей: повышенный пульс покоя и сниженную HRV. Хочу оценить сердечно-сосудистые риски.»",
                testsToOrder: ["ЭКГ", "Липидограмма", "Глюкоза натощак", "Измерение АД", "Общий анализ крови"],
                healthDataTypes: ["ЧСС в покое", "Вариабельность сердечного ритма (HRV)", "SpO₂", "Активная энергия"]
            )
        case "metabolic_syndrome_risk":
            return RiskInfo(
                explanation: "Паттерн данных указывает на признаки метаболического синдрома — совокупности факторов (избыток веса, низкая активность), существенно повышающих риск диабета 2 типа и сердечно-сосудистых заболеваний.",
                doctorType: "Эндокринолог, Кардиолог",
                actions: [
                    "Снизить потребление углеводов с высоким гликемическим индексом",
                    "Добавить силовые тренировки 2–3 раза в неделю",
                    "Измерять объём талии раз в месяц (норма: <80 см у женщин, <94 см у мужчин)",
                    "Ограничить алкоголь и сладкие напитки",
                ],
                doctorVisitReason: "«Данные трекера указывают на риск метаболического синдрома. Хочу сдать анализы для оценки углеводного и жирового обмена.»",
                testsToOrder: ["Глюкоза натощак", "HbA1c (гликированный гемоглобин)", "Липидограмма", "Инсулин натощак", "Измерение АД и объёма талии"],
                healthDataTypes: ["Масса тела", "ИМТ", "ЧСС в покое", "Уровень активности"]
            )
        case "cardiovascular_risk":
            return RiskInfo(
                explanation: "Избыточная масса тела в сочетании с другими показателями повышает нагрузку на сердечно-сосудистую систему, увеличивая долгосрочный риск инфаркта, инсульта и гипертонии.",
                doctorType: "Кардиолог",
                actions: [
                    "Регулярно измерять артериальное давление (утром и вечером)",
                    "Снизить потребление соли до 5 г в день",
                    "Добавить ежедневные прогулки от 30 минут",
                    "Снижение веса даже на 5–10% значительно уменьшает риск",
                ],
                doctorVisitReason: "«Трекер фиксирует повышенный кардиоваскулярный риск на фоне избыточного веса. Хочу пройти кардиологическое обследование и оценить риск гипертонии и атеросклероза.»",
                testsToOrder: ["ЭКГ", "ЭхоКГ", "Липидограмма", "Суточное мониторирование АД", "УЗИ сосудов шеи"],
                healthDataTypes: ["Масса тела", "ЧСС в покое", "Уровень активности"]
            )
        case "recovery_inefficiency_risk":
            return RiskInfo(
                explanation: "Восстановление организма после нагрузок замедлено. Это может быть связано с избыточной массой тела, нарушением сна, хроническим воспалением или гормональным дисбалансом.",
                doctorType: "Терапевт, Эндокринолог",
                actions: [
                    "Улучшить качество сна: прохладная тёмная комната, без экранов за час до сна",
                    "Добавить растяжку или йогу после тренировок",
                    "Контролировать потребление белка (1.2–1.6 г на кг массы тела)",
                    "Работать над снижением избыточного веса",
                ],
                doctorVisitReason: "«Трекер показывает медленное восстановление после нагрузок и сниженную HRV. Хочу исключить воспалительные и гормональные причины.»",
                testsToOrder: ["СРБ (С-реактивный белок)", "Ферритин", "Витамин D", "ТТГ", "Кортизол"],
                healthDataTypes: ["Вариабельность сердечного ритма (HRV)", "ЧСС в покое", "Продолжительность сна", "Масса тела"]
            )
        default:
            return RiskInfo(
                explanation: "Алгоритм обнаружил отклонение в одном или нескольких показателях здоровья. Рекомендуется проконсультироваться с врачом для уточнения.",
                doctorType: "Терапевт",
                actions: ["Проконсультироваться с врачом для оценки ситуации"],
                doctorVisitReason: "«Приложение для мониторинга здоровья обнаружило потенциальное отклонение. Хочу получить профессиональную оценку.»",
                testsToOrder: [],
                healthDataTypes: ["Данные Apple Health"]
            )
        }
    }
    // swiftlint:enable function_body_length
}
